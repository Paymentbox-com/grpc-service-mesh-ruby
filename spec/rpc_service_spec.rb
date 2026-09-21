# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::RPCService do
  def inbound(target, payload, metadata = {"Content-Type" => "application/x-protobuf"})
    ServiceMesh::Message.new(target: target, metadata: metadata, payload: payload)
  end

  def status_of(reply)
    Google::Rpc::Status.decode(reply.payload)
  end

  describe "binding" do
    it "binds nothing on the generated class itself" do
      service = Pbx::ApiKeyService.new

      expect(service.endpoints).to eq([])
      expect(service.subscribers).to eq([])
    end

    it "binds only the route a subclass defines" do
      service = Class.new(Pbx::ApiKeyService) do
        def search(request, metadata) = request
      end.new

      expect(service.endpoints.map(&:target)).to eq([Pbx::ApiKeyTargets::SEARCH])
      expect(service.subscribers).to eq([])
    end

    it "binds only the topic a subclass defines" do
      service = Class.new(Pbx::ApiKeyService) do
        def created(request, metadata)
        end
      end.new

      expect(service.endpoints).to eq([])
      expect(service.subscribers.map(&:target)).to eq([Pbx::ApiKeyTargets::CREATED])
    end
  end

  describe "an endpoint handler" do
    it "decodes the request, passes the inbound metadata, and encodes the response with Content-Type" do
      seen = nil
      service = Class.new(Pbx::ApiKeyService) do
        define_method(:search) do |request, metadata|
          seen = [request, metadata]
          Pbx::ApiKey.new(first_name: request.first_name.upcase, last_name: "found")
        end
      end.new
      metadata = {"Content-Type" => "application/x-protobuf", "Request-Id" => "r1"}

      reply = service.endpoints.first.handler.call(inbound(Pbx::ApiKeyTargets::SEARCH, Pbx::ApiKey.new(first_name: "ada").to_proto, metadata))

      expect(seen).to eq([Pbx::ApiKey.new(first_name: "ada"), metadata])
      expect(reply.target).to eq(Pbx::ApiKeyTargets::SEARCH)
      expect(reply.metadata).to eq({"Content-Type" => "application/x-protobuf"})
      expect(Pbx::ApiKey.decode(reply.payload)).to eq(Pbx::ApiKey.new(first_name: "ADA", last_name: "found"))
    end

    it "replies with the encoded Status and Grpc-Status when the handler raises a MeshError" do
      info = Google::Rpc::ErrorInfo.new(reason: "KEY_REVOKED", domain: "pbx")
      service = Class.new(Pbx::ApiKeyService) do
        define_method(:search) { |_request, _metadata| raise GrpcServiceMesh::MeshError.new(:NOT_FOUND, "no such key", info) }
      end.new

      reply = service.endpoints.first.handler.call(inbound(Pbx::ApiKeyTargets::SEARCH, Pbx::ApiKey.new.to_proto))

      expect(reply.metadata).to eq({"Content-Type" => "application/x-protobuf", "Grpc-Status" => "5"})
      status = status_of(reply)
      expect(status.code).to eq(5)
      expect(status.message).to eq("no such key")
      expect(status.details.map { |d| d.unpack(Google::Rpc::ErrorInfo) }).to eq([info])
    end

    it "reports any other exception as UNKNOWN with its message" do
      service = Class.new(Pbx::ApiKeyService) do
        def search(_request, _metadata) = raise("store is down")
      end.new

      reply = service.endpoints.first.handler.call(inbound(Pbx::ApiKeyTargets::SEARCH, Pbx::ApiKey.new.to_proto))

      expect(reply.metadata).to eq({"Content-Type" => "application/x-protobuf", "Grpc-Status" => "2"})
      expect(status_of(reply)).to eq(Google::Rpc::Status.new(code: 2, message: "store is down"))
    end

    it "reports a response of the wrong class as UNKNOWN" do
      service = Class.new(Pbx::ApiKeyService) do
        def search(_request, _metadata) = Google::Rpc::Status.new
      end.new

      reply = service.endpoints.first.handler.call(inbound(Pbx::ApiKeyTargets::SEARCH, Pbx::ApiKey.new.to_proto))

      expect(reply.metadata["Grpc-Status"]).to eq("2")
      expect(status_of(reply).message).to eq("search returned Google::Rpc::Status, expected Pbx::ApiKey")
    end

    it "reports a request that does not decode as UNKNOWN without calling the handler" do
      called = false
      service = Class.new(Pbx::ApiKeyService) do
        define_method(:search) { |request, _metadata| called = true and request }
      end.new

      reply = service.endpoints.first.handler.call(inbound(Pbx::ApiKeyTargets::SEARCH, "\x80".b))

      expect(called).to be(false)
      expect(reply.metadata["Grpc-Status"]).to eq("2")
      expect(status_of(reply).code).to eq(2)
    end
  end

  describe "a subscriber handler" do
    it "decodes the request, passes the inbound metadata, and returns nil" do
      seen = nil
      service = Class.new(Pbx::ApiKeyService) do
        define_method(:created) { |request, metadata| seen = [request, metadata] }
      end.new
      metadata = {"Content-Type" => "application/x-protobuf", "Event-Id" => "e1"}

      result = service.subscribers.first.handler.call(inbound(Pbx::ApiKeyTargets::CREATED, Pbx::ApiKey.new(first_name: "ada").to_proto, metadata))

      expect(result).to be_nil
      expect(seen).to eq([Pbx::ApiKey.new(first_name: "ada"), metadata])
    end

    it "lets an exception from the handler propagate unchanged" do
      service = Class.new(Pbx::ApiKeyService) do
        def created(_request, _metadata) = raise(IOError, "audit log closed")
      end.new

      expect { service.subscribers.first.handler.call(inbound(Pbx::ApiKeyTargets::CREATED, Pbx::ApiKey.new.to_proto)) }
        .to raise_error(IOError, "audit log closed")
    end
  end
end
