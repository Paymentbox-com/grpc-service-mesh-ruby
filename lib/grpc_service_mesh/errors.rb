# frozen_string_literal: true

module GrpcServiceMesh
  # Base of the errors this library raises for misuse of its own contract.
  # MeshError is an application error and stands apart from this tree.
  class Error < StandardError; end

  # A Target's transport metadata names a transport the router does not hold.
  class UnknownTransport < Error
    def initialize(name) = super("unknown transport #{name.inspect}")
  end

  # add_transport called with a name the router already holds.
  class DuplicateTransport < Error
    def initialize(name) = super("transport #{name.inspect} is already configured")
  end

  # A second binding registered for a Target already in the registry.
  class DuplicateTarget < Error
    def initialize(target) = super("target #{target.segments.join(".")} (#{target.kind}) is already registered")
  end

  # A second RPCRuntime constructed for a transport that already has one.
  class DuplicateRuntime < Error
    def initialize(name) = super("an RPCRuntime already exists for transport #{name.inspect}")
  end
end
