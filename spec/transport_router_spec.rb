# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::TransportRouter do
  let(:router) { GrpcServiceMesh.transport_router }

  def memory_client
    MemoryTransport::Client.new({"url" => "u"}, ServiceMaps::MEM, MemoryTransport::Bus.new)
  end

  it "returns the client added under the name" do
    client = memory_client
    GrpcServiceMesh.add_transport("mem", client)

    expect(router.client("mem")).to equal(client)
  end

  it "lists the names it holds" do
    GrpcServiceMesh.add_transport("mem", memory_client)
    GrpcServiceMesh.add_transport("http", memory_client)

    expect(router.names).to eq(%w[mem http])
  end

  it "replaces the client when a name is added again" do
    GrpcServiceMesh.add_transport("mem", memory_client)
    second = memory_client
    GrpcServiceMesh.add_transport("mem", second)

    expect(router.client("mem")).to equal(second)
  end

  it "raises UnknownTransport from client for a name it does not hold" do
    expect { router.client("http") }.to raise_error(GrpcServiceMesh::UnknownTransport, 'unknown transport "http"')
  end

  it "closes every added client" do
    mem = memory_client
    http = memory_client
    GrpcServiceMesh.add_transport("mem", mem)
    GrpcServiceMesh.add_transport("http", http)

    router.close

    expect(mem.closed?).to be(true)
    expect(http.closed?).to be(true)
  end

  it "closes every client when some fail and raises CloseFailed with each failure by name" do
    failing = Class.new { def close = raise(IOError, "flush failed") }
    http = memory_client
    GrpcServiceMesh.add_transport("mem", failing.new)
    GrpcServiceMesh.add_transport("http", http)
    GrpcServiceMesh.add_transport("queue", failing.new)

    expect { router.close }.to raise_error(GrpcServiceMesh::CloseFailed, "mem: flush failed; queue: flush failed") do |error|
      expect(error.failures.keys).to eq(%w[mem queue])
      expect(error.failures.values).to all(be_a(IOError))
    end
    expect(http.closed?).to be(true)
  end
end
