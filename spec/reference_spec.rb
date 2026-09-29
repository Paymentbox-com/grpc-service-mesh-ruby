# frozen_string_literal: true

# The reference generated code, served and called through one in-process transport.
RSpec.describe "the reference Shop service and client" do
  before do
    client = MemoryTransport::Client.new({"url" => "memory"}, ServiceMaps::MEM, MemoryTransport::Bus.new)
    GrpcServiceMesh.add_transport("mem", client)
  end

  let(:orders) do
    Class.new(Shop::OrderService) do
      attr_reader :events

      def initialize
        @events = []
      end

      def place(request)
        if request.id.empty?
          raise GrpcServiceMesh::MeshError.new(:INVALID_ARGUMENT, "id is required",
            Google::Rpc::BadRequest.new(field_violations: [{field: "id", description: "empty"}]),
            mesh_metadata: {"Retry-After" => "30"})
        end
        order = Shop::Order.new(id: request.id, item: request.mesh_metadata["Request-Id"])
        order.mesh_metadata = {"Region" => "west"}
        order
      end

      def placed(request)
        @events << [request, request.mesh_metadata["Event-Id"]]
      end
    end.new
  end

  it "serves a route and a topic through an RPCRuntime, carrying metadata both ways, and stops" do
    GrpcServiceMesh.register(orders)
    rpc_runtime = GrpcServiceMesh::RPCRuntime.new(transport: "mem", deployment_group: "shop", runtime: MemoryTransport.runtime_lambda)
    rpc_runtime.start

    place = Shop::Order.new(id: "o-1")
    place.mesh_metadata = {"Request-Id" => "r1"}
    placed = Shop::Order.new(id: "o-1")
    placed.mesh_metadata = {"Event-Id" => "e1"}

    found = Shop::OrderClient.place(place)
    Shop::OrderClient.placed(placed)

    expect(found).to eq(Shop::Order.new(id: "o-1", item: "r1"))
    expect(found.mesh_metadata).to eq({"Region" => "west", "Content-Type" => "application/x-protobuf"})
    expect(orders.events).to eq([[Shop::Order.new(id: "o-1"), "e1"]])
    expect(rpc_runtime.stop(1)).to be(true)
    expect { Shop::OrderClient.place(Shop::Order.new(id: "o-1")) }.to raise_error(MemoryTransport::NoReceiver)
  end

  it "carries a MeshError with its details and metadata from the handler to the caller" do
    GrpcServiceMesh.register(orders)
    GrpcServiceMesh::RPCRuntime.new(transport: "mem", deployment_group: "shop", runtime: MemoryTransport.runtime_lambda).start

    expect { Shop::OrderClient.place(Shop::Order.new) }.to raise_error(GrpcServiceMesh::MeshError) do |error|
      expect(error.code).to eq(:INVALID_ARGUMENT)
      expect(error.message).to eq("id is required")
      expect(error.details.first.unpack(Google::Rpc::BadRequest).field_violations.first.field).to eq("id")
      expect(error.mesh_metadata).to eq({"Retry-After" => "30", "Content-Type" => "application/x-protobuf", "Grpc-Status" => "3"})
    end
  end
end
