# frozen_string_literal: true

# The reference generated code, served and called through one in-process transport.
RSpec.describe "the reference Pbx service and client" do
  before do
    client = MemoryTransport::Client.new({"url" => "memory"}, ServiceMaps::NATS, MemoryTransport::Bus.new)
    GrpcServiceMesh.add_transport("nats", client: client, config: {"url" => "memory"}, runtime: MemoryTransport.runtime_lambda)
  end

  let(:api_keys) do
    Class.new(Pbx::ApiKeyService) do
      attr_reader :events

      def initialize
        @events = []
      end

      def search(request, metadata)
        if request.first_name.empty?
          raise GrpcServiceMesh::MeshError.new(:INVALID_ARGUMENT, "first_name is required",
            Google::Rpc::BadRequest.new(field_violations: [{field: "first_name", description: "empty"}]))
        end
        Pbx::ApiKey.new(first_name: request.first_name, last_name: metadata["Request-Id"])
      end

      def created(request, metadata)
        @events << [request, metadata["Event-Id"]]
      end
    end.new
  end

  it "serves a route and a topic through an RPCRuntime and stops" do
    GrpcServiceMesh.register(api_keys)
    rpc_runtime = GrpcServiceMesh::RPCRuntime.new(transport: "nats", deployment_group: "pbx")
    rpc_runtime.start

    found = Pbx::ApiKeyClient.search(Pbx::ApiKey.new(first_name: "ada"), metadata: {"Request-Id" => "r1"})
    Pbx::ApiKeyClient.created(Pbx::ApiKey.new(first_name: "ada"), metadata: {"Event-Id" => "e1"})

    expect(found).to eq(Pbx::ApiKey.new(first_name: "ada", last_name: "r1"))
    expect(api_keys.events).to eq([[Pbx::ApiKey.new(first_name: "ada"), "e1"]])
    expect(rpc_runtime.stop(1)).to be(true)
    expect { Pbx::ApiKeyClient.search(Pbx::ApiKey.new(first_name: "ada")) }.to raise_error(MemoryTransport::NoReceiver)
  end

  it "carries a MeshError with its details from the handler to the caller" do
    GrpcServiceMesh.register(api_keys)
    GrpcServiceMesh::RPCRuntime.new(transport: "nats", deployment_group: "pbx").start

    expect { Pbx::ApiKeyClient.search(Pbx::ApiKey.new) }.to raise_error(GrpcServiceMesh::MeshError) do |error|
      expect(error.code).to eq(:INVALID_ARGUMENT)
      expect(error.message).to eq("first_name is required")
      expect(error.details.first.unpack(Google::Rpc::BadRequest).field_violations.first.field).to eq("first_name")
    end
  end
end
