# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::TransportRouter do
  let(:router) { GrpcServiceMesh.transport_router }

  def memory_client
    MemoryTransport::Client.new({"url" => "u"}, ServiceMaps::NATS, MemoryTransport::Bus.new)
  end

  it "returns the client added under the name" do
    client = memory_client
    GrpcServiceMesh.add_transport("nats", client)

    expect(router.client("nats")).to equal(client)
  end

  it "lists the names it holds" do
    GrpcServiceMesh.add_transport("nats", memory_client)
    GrpcServiceMesh.add_transport("http", memory_client)

    expect(router.names).to eq(%w[nats http])
  end

  it "replaces the client when a name is added again" do
    GrpcServiceMesh.add_transport("nats", memory_client)
    second = memory_client
    GrpcServiceMesh.add_transport("nats", second)

    expect(router.client("nats")).to equal(second)
  end

  it "raises UnknownTransport from client for a name it does not hold" do
    expect { router.client("http") }.to raise_error(GrpcServiceMesh::UnknownTransport, 'unknown transport "http"')
  end

  it "closes every added client" do
    nats = memory_client
    http = memory_client
    GrpcServiceMesh.add_transport("nats", nats)
    GrpcServiceMesh.add_transport("http", http)

    router.close

    expect(nats.closed?).to be(true)
    expect(http.closed?).to be(true)
  end
end
