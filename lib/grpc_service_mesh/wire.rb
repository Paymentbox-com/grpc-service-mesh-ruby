# frozen_string_literal: true

module GrpcServiceMesh
  # Metadata keys and values the specification fixes on every message.
  module Wire
    CONTENT_TYPE_KEY = "Content-Type"
    CONTENT_TYPE = "application/x-protobuf"
    GRPC_STATUS_KEY = "Grpc-Status"

    # Metadata for a message carrying a payload of the method's type.
    def self.metadata(extra = {})
      extra.to_h.merge(CONTENT_TYPE_KEY => CONTENT_TYPE)
    end

    # Metadata for a reply whose payload is an encoded google.rpc.Status.
    def self.status_metadata(error)
      {CONTENT_TYPE_KEY => CONTENT_TYPE, GRPC_STATUS_KEY => error.proto.code.to_s}
    end
  end
end
