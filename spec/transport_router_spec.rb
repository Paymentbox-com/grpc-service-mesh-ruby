# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::TransportRouter do
  let(:bus) { MemoryTransport::Bus.new }
  let(:router) { GrpcServiceMesh.transport_router }

  def add_nats(config = {"url" => "nats://127.0.0.1:4222"})
    GrpcServiceMesh.add_transport("nats", config: config, service_map: ServiceMaps::NATS,
      runtime: MemoryTransport.runtime_lambda(bus), client: MemoryTransport.client_lambda(bus))
  end

  it "stores an entry under its name" do
    runtime = MemoryTransport.runtime_lambda(bus)
    client = MemoryTransport.client_lambda(bus)
    GrpcServiceMesh.add_transport("nats", config: {"url" => "u"}, service_map: ServiceMaps::NATS, runtime: runtime, client: client)

    expect(router.names).to eq(["nats"])
    expect(router.fetch("nats")).to eq(described_class::Transport.new(
      config: {"url" => "u"}, service_map: ServiceMaps::NATS, runtime: runtime, client: client
    ))
  end

  it "raises UnknownTransport from fetch for a name it does not hold" do
    expect { router.fetch("http") }.to raise_error(GrpcServiceMesh::UnknownTransport, 'unknown transport "http"')
  end

  it "raises UnknownTransport from client for a name it does not hold" do
    expect { router.client("http") }.to raise_error(GrpcServiceMesh::UnknownTransport, 'unknown transport "http"')
  end

  it "builds a standalone client once from the entry and keeps it" do
    add_nats({"url" => "u"})

    first = router.client("nats")
    second = router.client("nats")

    expect(first).to equal(second)
    expect(first).to be_a(MemoryTransport::Client)
    expect(first.config).to eq({"url" => "u"})
    expect(first.service_map).to equal(ServiceMaps::NATS)
  end

  it "closes the standalone clients it built and forgets them" do
    add_nats
    before = router.client("nats")

    router.close
    after = router.client("nats")

    expect(before.closed?).to be(true)
    expect(after).not_to equal(before)
    expect(after.closed?).to be(false)
  end

  it "leaves the RPCRuntime's client to its runtime on close" do
    add_nats
    GrpcServiceMesh::RPCRuntime.new(transport: "nats", deployment_group: "pbx")
    owned = router.client("nats")

    router.close

    expect(owned.closed?).to be(false)
  end

  it "hands out the RPCRuntime's client once one exists for the transport" do
    add_nats
    standalone = router.client("nats")

    rpc_runtime = GrpcServiceMesh::RPCRuntime.new(transport: "nats", deployment_group: "pbx")

    expect(router.runtime("nats")).to equal(rpc_runtime)
    expect(router.client("nats")).to equal(rpc_runtime.underlying.client)
    expect(router.client("nats")).not_to equal(standalone)
  end
end
