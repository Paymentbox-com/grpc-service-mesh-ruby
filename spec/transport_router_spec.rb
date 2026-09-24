# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::TransportRouter do
  let(:router) { GrpcServiceMesh.transport_router }

  def memory_client(config = {"url" => "u"})
    MemoryTransport::Client.new(config, ServiceMaps::NATS, MemoryTransport::Bus.new)
  end

  it "stores an entry under its name" do
    client = memory_client
    runtime = MemoryTransport.runtime_lambda
    GrpcServiceMesh.add_transport("nats", client: client, config: {"url" => "u"}, runtime: runtime)

    expect(router.names).to eq(["nats"])
    expect(router.fetch("nats")).to eq(described_class::Transport.new(client: client, config: {"url" => "u"}, runtime: runtime))
  end

  it "raises UnknownTransport from fetch for a name it does not hold" do
    expect { router.fetch("http") }.to raise_error(GrpcServiceMesh::UnknownTransport, 'unknown transport "http"')
  end

  it "raises UnknownTransport from client for a name it does not hold" do
    expect { router.client("http") }.to raise_error(GrpcServiceMesh::UnknownTransport, 'unknown transport "http"')
  end

  it "returns the client added under the name" do
    client = memory_client
    GrpcServiceMesh.add_transport("nats", client: client, config: {}, runtime: MemoryTransport.runtime_lambda)

    expect(router.client("nats")).to equal(client)
  end

  it "closes every added client" do
    nats = memory_client
    http = memory_client
    GrpcServiceMesh.add_transport("nats", client: nats, config: {}, runtime: MemoryTransport.runtime_lambda)
    GrpcServiceMesh.add_transport("http", client: http, config: {}, runtime: MemoryTransport.runtime_lambda)

    router.close

    expect(nats.closed?).to be(true)
    expect(http.closed?).to be(true)
  end
end
