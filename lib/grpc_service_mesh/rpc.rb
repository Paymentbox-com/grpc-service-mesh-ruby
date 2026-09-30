# frozen_string_literal: true

module GrpcServiceMesh
  # One rpc method as the generated code declares it. +owner+ is the class
  # the declaration appeared in. +consumer_group+ is the method's
  # consumer_group option, or nil when it has none.
  Rpc = Data.define(:name, :target, :input, :output, :kind, :owner, :consumer_group) do
    def initialize(name:, target:, input:, kind:, owner:, output: nil, consumer_group: nil)
      raise ServiceMesh::KindMismatch, "rpc #{name}: declared #{kind}, target is #{target.kind}" unless kind == target.kind

      super(name: name, target: target, input: input, output: output, kind: kind, owner: owner, consumer_group: consumer_group)
    end

    def route? = kind == :route
  end

  # Class-level declaration of rpcs, extended by RPCService and RPCClient.
  module RpcDSL
    # Declares one rpc. +name+ is the Ruby method name, +target+ the
    # ServiceMesh::Target, +input+ and +output+ the message classes, +kind+
    # :route or :topic, and +consumer_group+ the method's consumer_group
    # option. +output+ is not used for a topic.
    def rpc(name, target:, input:, kind:, output: nil, consumer_group: nil)
      rpc = Rpc.new(name: name, target: target, input: input, output: output, kind: kind, owner: self, consumer_group: consumer_group)
      own_rpcs[rpc.name] = rpc
      define_rpc(rpc)
      rpc
    end

    # Every declared rpc by name, including those of superclasses.
    def rpcs
      inherited = superclass.respond_to?(:rpcs) ? superclass.rpcs : {}
      inherited.merge(own_rpcs)
    end

    private

    def own_rpcs
      @own_rpcs ||= {}
    end

    def define_rpc(rpc)
    end
  end
end
