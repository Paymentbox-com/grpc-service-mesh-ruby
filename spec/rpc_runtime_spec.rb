# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::RPCRuntime do
  let(:client) { MemoryTransport::Client.new({"url" => "nats://127.0.0.1:4222"}, ServiceMaps::NATS, MemoryTransport::Bus.new) }

  let(:runtime) { MemoryTransport.runtime_lambda }

  before { GrpcServiceMesh.add_transport("nats", client) }

  it "builds the transport runtime with its deployment group's bindings and the group in the config" do
    orders = Class.new(Shop::OrderService) do
      def place(request, metadata) = request

      def placed(request, metadata)
      end
    end
    audit_target = ServiceMesh::Target.new(segments: %w[audit AuditService Record], kind: :topic,
      metadata: {"deployment_group" => "audit", "transport" => "nats"})
    audit = Class.new(GrpcServiceMesh::RPCService) do
      rpc :record, target: audit_target, input: Shop::Order, kind: :topic
      def record(request, metadata)
      end
    end
    GrpcServiceMesh.register(orders.new)
    GrpcServiceMesh.register(audit.new)

    rpc_runtime = described_class.new(transport: "nats", deployment_group: "shop", runtime: runtime,
      config: {"url" => "nats://127.0.0.1:4222"})

    expect(rpc_runtime.transport).to eq("nats")
    expect(rpc_runtime.deployment_group).to eq("shop")
    expect(rpc_runtime.underlying).to be_a(MemoryTransport::Runtime)
    expect(rpc_runtime.underlying.config).to eq({"url" => "nats://127.0.0.1:4222", "deployment_group" => "shop"})
    expect(rpc_runtime.underlying.endpoints.map(&:target)).to eq([Shop::OrderTargets::PLACE])
    expect(rpc_runtime.underlying.subscribers.map(&:target)).to eq([Shop::OrderTargets::PLACED])
  end

  it "hands the router's client to the runtime lambda" do
    rpc_runtime = described_class.new(transport: "nats", deployment_group: "shop", runtime: runtime)

    expect(rpc_runtime.underlying.client).to equal(client)
  end

  it "sets deployment_group over the one in the given config and leaves the given config unchanged" do
    config = {"deployment_group" => "configured"}.freeze

    rpc_runtime = described_class.new(transport: "nats", deployment_group: "shop", runtime: runtime, config: config)

    expect(rpc_runtime.underlying.config).to eq({"deployment_group" => "shop"})
    expect(config).to eq({"deployment_group" => "configured"})
  end

  it "raises ArgumentError when runtime: is not callable" do
    expect { described_class.new(transport: "nats", deployment_group: "shop", runtime: nil) }
      .to raise_error(ArgumentError, /runtime: must be a callable/)
  end

  it "raises UnknownTransport for a transport the router does not hold" do
    calls = []
    counting = ->(*args, **kwargs) { calls << [args, kwargs] }

    expect { described_class.new(transport: "http", deployment_group: "shop", runtime: counting) }
      .to raise_error(GrpcServiceMesh::UnknownTransport, 'unknown transport "http"')
    expect(calls).to eq([])
  end

  it "passes the runtime lambda's exception through" do
    failure = StandardError.new("bad url")
    failing = ->(_client, _config, endpoints:, subscribers:) { raise failure }

    expect { described_class.new(transport: "nats", deployment_group: "shop", runtime: failing) }
      .to raise_error(failure)
  end

  it "delegates start, stop, running?, and client to the transport runtime" do
    rpc_runtime = described_class.new(transport: "nats", deployment_group: "shop", runtime: runtime)
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

  it "leaves the client closed after stop" do
    rpc_runtime = described_class.new(transport: "nats", deployment_group: "shop", runtime: runtime)
    rpc_runtime.start

    rpc_runtime.stop(1)

    expect(client.closed?).to be(true)
  end

  describe "with bindings given in place of the registry's" do
    let(:orders) do
      Class.new(Shop::OrderService) do
        def place(request, metadata) = request

        def placed(request, metadata)
        end
      end
    end

    let(:handler) { ->(_message) {} }

    let(:given_endpoint) do
      ServiceMesh::Endpoint.new(handler: handler, target: ServiceMesh::Target.new(segments: %w[shop Given Get], kind: :route,
        metadata: {"deployment_group" => "shop", "transport" => "nats"}))
    end

    let(:given_subscriber) do
      ServiceMesh::Subscriber.new(handler: handler, target: ServiceMesh::Target.new(segments: %w[shop Given Made], kind: :topic,
        metadata: {"deployment_group" => "shop", "transport" => "nats"}))
    end

    before { GrpcServiceMesh.register(orders.new) }

    it "serves the given endpoints and the registry's subscribers" do
      rpc_runtime = described_class.new(transport: "nats", deployment_group: "shop", runtime: runtime,
        endpoints: [given_endpoint])

      expect(rpc_runtime.underlying.endpoints).to eq([given_endpoint])
      expect(rpc_runtime.underlying.subscribers.map(&:target)).to eq([Shop::OrderTargets::PLACED])
    end

    it "serves the given subscribers and the registry's endpoints" do
      rpc_runtime = described_class.new(transport: "nats", deployment_group: "shop", runtime: runtime,
        subscribers: [given_subscriber])

      expect(rpc_runtime.underlying.endpoints.map(&:target)).to eq([Shop::OrderTargets::PLACE])
      expect(rpc_runtime.underlying.subscribers).to eq([given_subscriber])
    end

    it "serves the given endpoints and subscribers" do
      rpc_runtime = described_class.new(transport: "nats", deployment_group: "shop", runtime: runtime,
        endpoints: [given_endpoint], subscribers: [given_subscriber])

      expect(rpc_runtime.underlying.endpoints).to eq([given_endpoint])
      expect(rpc_runtime.underlying.subscribers).to eq([given_subscriber])
    end

    it "serves no endpoints for endpoints: []" do
      rpc_runtime = described_class.new(transport: "nats", deployment_group: "shop", runtime: runtime, endpoints: [])

      expect(rpc_runtime.underlying.endpoints).to eq([])
      expect(rpc_runtime.underlying.subscribers.map(&:target)).to eq([Shop::OrderTargets::PLACED])
    end

    it "raises ArgumentError naming the segments and deployment_group of an endpoint in another group" do
      calls = []
      counting = ->(*args, **kwargs) { calls << [args, kwargs] }
      billing = ServiceMesh::Endpoint.new(handler: handler, target: ServiceMesh::Target.new(segments: %w[billing Invoice Get],
        kind: :route, metadata: {"deployment_group" => "billing", "transport" => "nats"}))

      expect { described_class.new(transport: "nats", deployment_group: "shop", runtime: counting, endpoints: [billing]) }
        .to raise_error(ArgumentError, 'endpoint ["billing", "Invoice", "Get"] has deployment_group "billing", want "shop"')
      expect(calls).to eq([])
    end

    it "raises ArgumentError naming the segments and transport of a subscriber on another transport" do
      calls = []
      counting = ->(*args, **kwargs) { calls << [args, kwargs] }
      http = ServiceMesh::Subscriber.new(handler: handler, target: ServiceMesh::Target.new(segments: %w[shop Order Made],
        kind: :topic, metadata: {"deployment_group" => "shop", "transport" => "http"}))

      expect { described_class.new(transport: "nats", deployment_group: "shop", runtime: counting, subscribers: [http]) }
        .to raise_error(ArgumentError, 'subscriber ["shop", "Order", "Made"] has transport "http", want "nats"')
      expect(calls).to eq([])
    end
  end
end
