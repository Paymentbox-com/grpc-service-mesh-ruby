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

    # Adds the bindings of +service+, an RPCService instance. Raises
    # DuplicateTarget when a binding's Target is already registered; nothing
    # from +service+ is kept in that case.
    def register(service)
      endpoints = service.endpoints
      subscribers = service.subscribers
      @lock.synchronize do
        taken = @endpoints + @subscribers
        (endpoints + subscribers).each do |binding|
          raise DuplicateTarget.new(binding.target) if taken.any? { |b| b.target.same_channel?(binding.target) }

          taken << binding
        end
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
