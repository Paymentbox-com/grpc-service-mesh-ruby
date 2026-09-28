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

    # The metadata Hash set on this object, or a frozen empty Hash when none is set.
    def mesh_metadata
      @mesh_metadata || EMPTY
    end

    # Sets the metadata. Takes a Hash, or nil for none.
    def mesh_metadata=(metadata)
      @mesh_metadata = Hash(metadata)
    end
  end
end
