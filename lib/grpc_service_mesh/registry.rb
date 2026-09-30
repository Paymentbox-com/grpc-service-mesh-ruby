# frozen_string_literal: true

module GrpcServiceMesh
  # Collects every Endpoint and Subscriber the process serves. The process
  # registry is GrpcServiceMesh.registry.
  class Registry
    def initialize
      @endpoints = []
      @subscribers = []
    end

    # Adds the endpoints and subscribers of +service+, an RPCService
    # instance. +consumer_groups+ maps a target of the service to the
    # consumer group of its endpoint or subscriber, replacing the one the
    # generated code carries. "" removes it, so the runtime's deployment group
    # applies, and ServiceMesh::CONSUMER_GROUP_NONE means no group. Raises
    # ArgumentError, and registers nothing, when a target is not one of the
    # service's. Every endpoint and subscriber is kept, so two registrations of
    # one target hand the transport two of them.
    def register(service, consumer_groups: {})
      endpoints = service.endpoints
      subscribers = service.subscribers
      consumer_groups.each do |target, group|
        found = false
        apply = lambda do |served|
          next served unless served.target.same_channel?(target)

          found = true
          with_group(served, group)
        end
        endpoints = endpoints.map(&apply)
        subscribers = subscribers.map(&apply)
        raise ArgumentError, "consumer_groups names target #{target.segments.inspect}, which is not an rpc method of #{service.class}" unless found
      end
      @endpoints.concat(endpoints)
      @subscribers.concat(subscribers)
      nil
    end

    # Every registered Endpoint.
    attr_reader :endpoints

    # Every registered Subscriber.
    attr_reader :subscribers

    private

    def with_group(served, group)
      metadata = served.metadata.to_h.except(ServiceMesh::CONSUMER_GROUP_KEY)
      metadata[ServiceMesh::CONSUMER_GROUP_KEY] = group unless group.to_s.empty?
      served.with(metadata: metadata)
    end
  end
end
