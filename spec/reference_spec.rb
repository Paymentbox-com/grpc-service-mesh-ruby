# frozen_string_literal: true

# The reference generated code, served and called through one in-process transport.
RSpec.describe "the reference Shop service and client" do
  before do
    client = MemoryTransport::Client.new({"url" => "memory"}, ServiceMaps::NATS, MemoryTransport::Bus.new)
    GrpcServiceMesh.add_transport("nats", client: client, config: {"url" => "memory"}, runtime: MemoryTransport.runtime_lambda)
  end

  let(:orders) do
    Class.new(Shop::OrderService) do
      attr_reader :events

      def initialize
        @events = []
      end

      def place(request, metadata)
        if request.id.empty?
          raise GrpcServiceMesh::MeshError.new(:INVALID_ARGUMENT, "id is required",
            Google::Rpc::BadRequest.new(field_violations: [{field: "id", description: "empty"}]))
        end
        Shop::Order.new(id: request.id, item: metadata["Request-Id"])
      end

      def placed(request, metadata)
        @events << [request, metadata["Event-Id"]]
      end
    end.new
  end

  it "serves a route and a topic through an RPCRuntime and stops" do
    GrpcServiceMesh.register(orders)
    rpc_runtime = GrpcServiceMesh::RPCRuntime.new(transport: "nats", deployment_group: "shop")
    rpc_runtime.start

    found = Shop::OrderClient.place(Shop::Order.new(id: "o-1"), metadata: {"Request-Id" => "r1"})
    Shop::OrderClient.placed(Shop::Order.new(id: "o-1"), metadata: {"Event-Id" => "e1"})

    expect(found).to eq(Shop::Order.new(id: "o-1", item: "r1"))
    expect(orders.events).to eq([[Shop::Order.new(id: "o-1"), "e1"]])
    expect(rpc_runtime.stop(1)).to be(true)
    expect { Shop::OrderClient.place(Shop::Order.new(id: "o-1")) }.to raise_error(MemoryTransport::NoReceiver)
  end

  it "carries a MeshError with its details from the handler to the caller" do
    GrpcServiceMesh.register(orders)
    GrpcServiceMesh::RPCRuntime.new(transport: "nats", deployment_group: "shop").start

    expect { Shop::OrderClient.place(Shop::Order.new) }.to raise_error(GrpcServiceMesh::MeshError) do |error|
      expect(error.code).to eq(:INVALID_ARGUMENT)
      expect(error.message).to eq("id is required")
      expect(error.details.first.unpack(Google::Rpc::BadRequest).field_violations.first.field).to eq("id")
    end
  end
end
