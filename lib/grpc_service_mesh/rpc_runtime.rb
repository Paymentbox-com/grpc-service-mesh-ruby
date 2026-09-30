# frozen_string_literal: true

module GrpcServiceMesh
  # The service process for one transport and one deployment group. new
  # takes the transport's client from the process router and every endpoint
  # and subscriber in the process registry whose target is on that transport,
  # and builds the transport's Runtime from them with the +runtime+
  # constructor.
  class RPCRuntime
    attr_reader :transport, :deployment_group, :t_runtime

    # +runtime+ is ->(client, config, endpoints:, subscribers:) returning the
    # transport's Runtime. It receives +config+ with deployment_group set.
    # Endpoints and subscribers of other transports are left for those
    # transports' runtimes. Raises ArgumentError when +runtime+ is not
    # callable, UnknownTransport, and whatever +runtime+ raises.
    def initialize(transport:, deployment_group:, runtime:, config: {})
      raise ArgumentError, "runtime: must be a callable that builds the transport's Runtime, got #{runtime.inspect}" unless runtime.respond_to?(:call)

      registry = GrpcServiceMesh.registry
      client = GrpcServiceMesh.transport_router.client(transport)
      @transport = transport
      @deployment_group = deployment_group
      on_transport = ->(served) { served.target.metadata["transport"] == transport }
      @t_runtime = runtime.call(
        client,
        config.to_h.merge(ServiceMesh::DEPLOYMENT_GROUP_KEY => deployment_group),
        endpoints: registry.endpoints.select(&on_transport),
        subscribers: registry.subscribers.select(&on_transport)
      )
    end

    def start = @t_runtime.start

    def stop(drain) = @t_runtime.stop(drain)

    def running? = @t_runtime.running?

    def client = @t_runtime.client
  end
end
