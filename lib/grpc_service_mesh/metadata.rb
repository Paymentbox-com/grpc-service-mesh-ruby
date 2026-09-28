# frozen_string_literal: true

module GrpcServiceMesh
  # Message metadata carried on a message object. Generated code includes it
  # into every message class an rpc takes or returns; MeshError includes it
  # too. The library sets it on the objects it builds and reads it from the
  # objects the application gives it, and never writes to an object the
  # application built.
  module Metadata
    EMPTY = {}.freeze
    private_constant :EMPTY

    # The metadata Hash of this object. On first read it is a new empty Hash
    # stored on the object, so keys can be written into it directly. A frozen
    # object with none set has a frozen empty Hash.
    def mesh_metadata
      return @mesh_metadata if instance_variable_defined?(:@mesh_metadata) && @mesh_metadata
      return EMPTY if frozen?

      @mesh_metadata = {}
    end

    # Sets the metadata. Takes a Hash, or nil for none.
    def mesh_metadata=(metadata)
      @mesh_metadata = Hash(metadata)
    end
  end
end
