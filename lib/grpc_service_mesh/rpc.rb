# frozen_string_literal: true

module GrpcServiceMesh
  # One rpc method as the generated code declares it. +owner+ is the class
  # the declaration appeared in.
  Rpc = Data.define(:name, :target, :input, :output, :kind, :owner) do
    def initialize(name:, target:, input:, kind:, owner:, output: nil)
      name = name.to_sym
      kind = kind.to_sym
      unless ServiceMesh::KINDS.include?(kind)
        raise ArgumentError, "rpc #{name}: kind must be one of #{ServiceMesh::KINDS.inspect}, got #{kind.inspect}"
      end
      raise ArgumentError, "rpc #{name}: kind #{kind} does not match target kind #{target.kind}" unless kind == target.kind
      raise ArgumentError, "rpc #{name}: a route needs an output message class" if kind == :route && output.nil?

      super(name: name, target: target, input: input, output: output, kind: kind, owner: owner)
    end

    def route? = kind == :route
  end

  # Class-level declaration of rpcs, extended by RPCService and RPCClient.
  module RpcDSL
    # Declares one rpc. +name+ is the Ruby method name, +target+ the
    # ServiceMesh::Target, +input+ and +output+ the message classes, +kind+
    # :route or :topic. +output+ is not used for a topic.
    def rpc(name, target:, input:, kind:, output: nil)
      rpc = Rpc.new(name: name, target: target, input: input, output: output, kind: kind, owner: self)
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
