# frozen_string_literal: true

module GrpcServiceMesh
  # The service process for one transport and one deployment group. new
  # takes the transport's client from the process router and the matching
  # bindings from the process registry, and builds the transport's Runtime
  # from them with the +runtime+ constructor.
  class RPCRuntime
    attr_reader :transport, :deployment_group, :underlying

    # +runtime+ is ->(client, config, endpoints:, subscribers:) returning the
    # transport's Runtime. It receives +config+ with deployment_group set.
    # Raises UnknownTransport and whatever +runtime+ raises.
    def initialize(transport:, deployment_group:, runtime:, config: {})
      raise ArgumentError, "runtime: must be a callable that builds the transport's Runtime, got #{runtime.inspect}" unless runtime.respond_to?(:call)

      registry = GrpcServiceMesh.registry
      client = GrpcServiceMesh.transport_router.client(transport)
      @transport = transport
      @deployment_group = deployment_group
      @underlying = runtime.call(
        client,
        config.to_h.merge(ServiceMesh::DEPLOYMENT_GROUP_KEY => deployment_group),
        endpoints: registry.endpoints(deployment_group),
        subscribers: registry.subscribers(deployment_group)
      )
    end

    def start = @underlying.start

    def stop(drain) = @underlying.stop(drain)

    def running? = @underlying.running?

    def client = @underlying.client
  end
end
