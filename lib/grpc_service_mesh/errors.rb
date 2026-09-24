# frozen_string_literal: true

module GrpcServiceMesh
  # Base of the errors this library raises for misuse of its own contract.
  # MeshError is an application error and stands apart from this tree.
  class Error < StandardError; end

  # A Target's transport metadata names a transport the router does not hold.
  class UnknownTransport < Error
    def initialize(name) = super("unknown transport #{name.inspect}")
  end
end
