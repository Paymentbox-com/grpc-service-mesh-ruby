# frozen_string_literal: true

module GrpcServiceMesh
  # The service process for one transport and one deployment group. new
  # takes the transport's client from the process router and the matching
  # bindings from the process registry, and builds the transport's Runtime
  # from them with the +runtime+ constructor.
  class RPCRuntime
    attr_reader :transport, :deployment_group, :t_runtime

    # +runtime+ is ->(client, config, endpoints:, subscribers:) returning the
    # transport's Runtime. It receives +config+ with deployment_group set.
    # +endpoints+ and +subscribers+, when given, replace the registry's list
    # of that kind, and [] serves none. Raises ArgumentError for a given
    # binding whose Target's deployment_group or transport is not this
    # runtime's, UnknownTransport, and whatever +runtime+ raises.
    def initialize(transport:, deployment_group:, runtime:, config: {}, endpoints: nil, subscribers: nil)
      raise ArgumentError, "runtime: must be a callable that builds the transport's Runtime, got #{runtime.inspect}" unless runtime.respond_to?(:call)

      registry = GrpcServiceMesh.registry
      client = GrpcServiceMesh.transport_router.client(transport)
      @transport = transport
      @deployment_group = deployment_group
      endpoints&.each { |binding| check_target("endpoint", binding.target) }
      subscribers&.each { |binding| check_target("subscriber", binding.target) }
      @t_runtime = runtime.call(
        client,
        config.to_h.merge(ServiceMesh::DEPLOYMENT_GROUP_KEY => deployment_group),
        endpoints: endpoints || registry.endpoints(deployment_group),
        subscribers: subscribers || registry.subscribers(deployment_group)
      )
    end

    def start = @t_runtime.start

    def stop(drain) = @t_runtime.stop(drain)

    def running? = @t_runtime.running?

    def client = @t_runtime.client

    private

    def check_target(kind, target)
      {ServiceMesh::DEPLOYMENT_GROUP_KEY => @deployment_group, "transport" => @transport}.each do |key, want|
        got = target.metadata[key]
        next if got == want

        raise ArgumentError, "#{kind} #{target.segments.inspect} has #{key} #{got.inspect}, want #{want.inspect}"
      end
    end
  end
end
