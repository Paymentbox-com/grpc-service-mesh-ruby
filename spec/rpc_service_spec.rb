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
      service = Shop::OrderService.new

      expect(service.endpoints).to eq([])
      expect(service.subscribers).to eq([])
    end

    it "binds only the route a subclass defines" do
      service = Class.new(Shop::OrderService) do
        def place(request, metadata) = request
      end.new

      expect(service.endpoints.map(&:target)).to eq([Shop::OrderTargets::PLACE])
      expect(service.subscribers).to eq([])
    end

    it "binds only the topic a subclass defines" do
      service = Class.new(Shop::OrderService) do
        def placed(request, metadata)
        end
      end.new

      expect(service.endpoints).to eq([])
      expect(service.subscribers.map(&:target)).to eq([Shop::OrderTargets::PLACED])
    end
  end

  describe "an endpoint handler" do
    it "decodes the request, passes the inbound metadata, and encodes the response with Content-Type" do
      seen = nil
      service = Class.new(Shop::OrderService) do
        define_method(:place) do |request, metadata|
          seen = [request, metadata]
          Shop::Order.new(id: request.id.upcase, item: "found")
        end
      end.new
      metadata = {"Content-Type" => "application/x-protobuf", "Request-Id" => "r1"}

      reply = service.endpoints.first.handler.call(inbound(Shop::OrderTargets::PLACE, Shop::Order.new(id: "o-1").to_proto, metadata))

      expect(seen).to eq([Shop::Order.new(id: "o-1"), metadata])
      expect(reply.target).to eq(Shop::OrderTargets::PLACE)
      expect(reply.metadata).to eq({"Content-Type" => "application/x-protobuf"})
      expect(Shop::Order.decode(reply.payload)).to eq(Shop::Order.new(id: "O-1", item: "found"))
    end

    it "replies with the encoded Status and Grpc-Status when the handler raises a MeshError" do
      info = Google::Rpc::ErrorInfo.new(reason: "ORDER_CANCELLED", domain: "shop")
      service = Class.new(Shop::OrderService) do
        define_method(:place) { |_request, _metadata| raise GrpcServiceMesh::MeshError.new(:NOT_FOUND, "no such order", info) }
      end.new

      reply = service.endpoints.first.handler.call(inbound(Shop::OrderTargets::PLACE, Shop::Order.new.to_proto))

      expect(reply.metadata).to eq({"Content-Type" => "application/x-protobuf", "Grpc-Status" => "5"})
      status = status_of(reply)
      expect(status.code).to eq(5)
      expect(status.message).to eq("no such order")
      expect(status.details.map { |d| d.unpack(Google::Rpc::ErrorInfo) }).to eq([info])
    end

    it "reports any other exception as UNKNOWN with its message" do
      service = Class.new(Shop::OrderService) do
        def place(_request, _metadata) = raise("store is down")
      end.new

      reply = service.endpoints.first.handler.call(inbound(Shop::OrderTargets::PLACE, Shop::Order.new.to_proto))

      expect(reply.metadata).to eq({"Content-Type" => "application/x-protobuf", "Grpc-Status" => "2"})
      expect(status_of(reply)).to eq(Google::Rpc::Status.new(code: 2, message: "store is down"))
    end

    it "reports a response of the wrong class as UNKNOWN" do
      service = Class.new(Shop::OrderService) do
        def place(_request, _metadata) = Google::Rpc::Status.new
      end.new

      reply = service.endpoints.first.handler.call(inbound(Shop::OrderTargets::PLACE, Shop::Order.new.to_proto))

      expect(reply.metadata["Grpc-Status"]).to eq("2")
      expect(status_of(reply).message).to eq("place returned Google::Rpc::Status, expected Shop::Order")
    end

    it "reports a request that does not decode as UNKNOWN without calling the handler" do
      called = false
      service = Class.new(Shop::OrderService) do
        define_method(:place) { |request, _metadata| called = true and request }
      end.new

      reply = service.endpoints.first.handler.call(inbound(Shop::OrderTargets::PLACE, "\x80".b))

      expect(called).to be(false)
      expect(reply.metadata["Grpc-Status"]).to eq("2")
      expect(status_of(reply).code).to eq(2)
    end
  end

  describe "a subscriber handler" do
    it "decodes the request, passes the inbound metadata, and returns nil" do
      seen = nil
      service = Class.new(Shop::OrderService) do
        define_method(:placed) { |request, metadata| seen = [request, metadata] }
      end.new
      metadata = {"Content-Type" => "application/x-protobuf", "Event-Id" => "e1"}

      result = service.subscribers.first.handler.call(inbound(Shop::OrderTargets::PLACED, Shop::Order.new(id: "o-1").to_proto, metadata))

      expect(result).to be_nil
      expect(seen).to eq([Shop::Order.new(id: "o-1"), metadata])
    end

    it "lets an exception from the handler propagate unchanged" do
      service = Class.new(Shop::OrderService) do
        def placed(_request, _metadata) = raise(IOError, "audit log closed")
      end.new

      expect { service.subscribers.first.handler.call(inbound(Shop::OrderTargets::PLACED, Shop::Order.new.to_proto)) }
        .to raise_error(IOError, "audit log closed")
    end
  end
end
