# frozen_string_literal: true

module GrpcServiceMesh
  # The service process for one transport and one deployment group. new
  # takes the matching bindings from the process registry and builds the
  # transport's Runtime on the entry's client through the process router.
  class RPCRuntime
    attr_reader :transport, :deployment_group, :underlying

    # Raises UnknownTransport and whatever the transport's runtime
    # constructor raises.
    def initialize(transport:, deployment_group:)
      registry = GrpcServiceMesh.registry
      entry = GrpcServiceMesh.transport_router.fetch(transport)
      @transport = transport
      @deployment_group = deployment_group
      @underlying = entry.runtime.call(
        entry.client,
        entry.config.merge(ServiceMesh::DEPLOYMENT_GROUP_KEY => deployment_group),
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
