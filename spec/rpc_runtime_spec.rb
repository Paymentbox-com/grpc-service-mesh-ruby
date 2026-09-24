# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::RPCRuntime do
  let(:bus) { MemoryTransport::Bus.new }

  before do
    GrpcServiceMesh.add_transport("nats", config: {"url" => "nats://127.0.0.1:4222"}, service_map: ServiceMaps::NATS,
      runtime: MemoryTransport.runtime_lambda(bus), client: MemoryTransport.client_lambda(bus))
  end

  it "builds the transport runtime with its deployment group's bindings, the transport's map, and the group in the config" do
    api_keys = Class.new(Pbx::ApiKeyService) do
      def search(request, metadata) = request

      def created(request, metadata)
      end
    end
    audit_target = ServiceMesh::Target.new(segments: %w[audit AuditService Record], kind: :topic,
      metadata: {"deployment_group" => "audit", "transport" => "nats"})
    audit = Class.new(GrpcServiceMesh::RPCService) do
      rpc :record, target: audit_target, input: Pbx::ApiKey, kind: :topic
      def record(request, metadata)
      end
    end
    GrpcServiceMesh.register(api_keys.new)
    GrpcServiceMesh.register(audit.new)

    rpc_runtime = described_class.new(transport: "nats", deployment_group: "pbx")

    expect(rpc_runtime.transport).to eq("nats")
    expect(rpc_runtime.deployment_group).to eq("pbx")
    expect(rpc_runtime.underlying).to be_a(MemoryTransport::Runtime)
    expect(rpc_runtime.underlying.config).to eq({"url" => "nats://127.0.0.1:4222", "deployment_group" => "pbx"})
    expect(rpc_runtime.underlying.service_map).to equal(ServiceMaps::NATS)
    expect(rpc_runtime.underlying.endpoints.map(&:target)).to eq([Pbx::ApiKeyTargets::SEARCH])
    expect(rpc_runtime.underlying.subscribers.map(&:target)).to eq([Pbx::ApiKeyTargets::CREATED])
  end

  it "raises UnknownTransport for a transport the router does not hold" do
    expect { described_class.new(transport: "http", deployment_group: "pbx") }
      .to raise_error(GrpcServiceMesh::UnknownTransport, 'unknown transport "http"')
  end

  it "delegates start, stop, running?, and client to the transport runtime" do
    rpc_runtime = described_class.new(transport: "nats", deployment_group: "pbx")
    underlying = rpc_runtime.underlying

    expect(rpc_runtime.running?).to be(false)
    rpc_runtime.start
    expect(underlying.starts).to eq(1)
    expect(rpc_runtime.running?).to be(true)
    expect(rpc_runtime.client).to equal(underlying.client)
    expect(rpc_runtime.stop(2.5)).to be(true)
    expect(underlying.stops).to eq([2.5])
    expect(rpc_runtime.running?).to be(false)
  end
end
