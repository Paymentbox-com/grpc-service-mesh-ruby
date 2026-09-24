# frozen_string_literal: true

module GrpcServiceMesh
  # Collects every Endpoint and Subscriber the process serves. The process
  # registry is GrpcServiceMesh.registry.
  class Registry
    def initialize
      @lock = Mutex.new
      @endpoints = []
      @subscribers = []
    end

    # Adds the bindings of +service+, an RPCService instance. Every binding
    # is kept, so two registrations of one Target hand the transport two
    # bindings for it.
    def register(service)
      endpoints = service.endpoints
      subscribers = service.subscribers
      @lock.synchronize do
        @endpoints.concat(endpoints)
        @subscribers.concat(subscribers)
      end
      nil
    end

    # Endpoints whose Target carries +deployment_group+.
    def endpoints(deployment_group)
      @lock.synchronize { @endpoints.select { |e| in_group?(e, deployment_group) } }
    end

    # Subscribers whose Target carries +deployment_group+.
    def subscribers(deployment_group)
      @lock.synchronize { @subscribers.select { |s| in_group?(s, deployment_group) } }
    end

    private

    def in_group?(binding, deployment_group)
      binding.target.metadata[ServiceMesh::DEPLOYMENT_GROUP_KEY] == deployment_group
    end
  end
end
