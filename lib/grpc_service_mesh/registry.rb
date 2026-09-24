# frozen_string_literal: true

module GrpcServiceMesh
  # Collects every Endpoint and Subscriber the process serves. The process
  # registry is GrpcServiceMesh.registry.
  class Registry
    def initialize
      @endpoints = []
      @subscribers = []
    end

    # Adds the bindings of +service+, an RPCService instance. Every binding
    # is kept, so two registrations of one Target hand the transport two
    # bindings for it.
    def register(service)
      @endpoints.concat(service.endpoints)
      @subscribers.concat(service.subscribers)
      nil
    end

    # Endpoints whose Target carries +deployment_group+.
    def endpoints(deployment_group)
      @endpoints.select { |e| in_group?(e, deployment_group) }
    end

    # Subscribers whose Target carries +deployment_group+.
    def subscribers(deployment_group)
      @subscribers.select { |s| in_group?(s, deployment_group) }
    end

    private

    def in_group?(binding, deployment_group)
      binding.target.metadata[ServiceMesh::DEPLOYMENT_GROUP_KEY] == deployment_group
    end
  end
end
