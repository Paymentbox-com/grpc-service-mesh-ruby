# frozen_string_literal: true

module GrpcServiceMesh
  # The service process for one transport and one deployment group. new
  # takes the matching bindings from the process registry, builds the
  # transport's Runtime through the process router, and records itself on the
  # router as the transport's client source.
  class RPCRuntime
    attr_reader :transport, :deployment_group, :underlying

    # Raises UnknownTransport and whatever the transport's runtime
    # constructor raises. A second runtime for the same transport becomes
    # the one whose client the router hands out.
    def initialize(transport:, deployment_group:)
      router = GrpcServiceMesh.transport_router
      registry = GrpcServiceMesh.registry
      entry = router.fetch(transport)
      @transport = transport
      @deployment_group = deployment_group
      @underlying = entry.runtime.call(
        entry.config.merge(ServiceMesh::DEPLOYMENT_GROUP_KEY => deployment_group),
        entry.service_map,
        endpoints: registry.endpoints(deployment_group),
        subscribers: registry.subscribers(deployment_group)
      )
      router.attach_runtime(transport, self)
    end

    def start = @underlying.start

    def stop(drain) = @underlying.stop(drain)

    def running? = @underlying.running?

    def client = @underlying.client
  end
end
