# frozen_string_literal: true

module GrpcServiceMesh
  # The start of an outgoing metadata key that is a transport option. A client
  # method passes each such key, with the prefix removed, to the transport's
  # request or publish options, and sends the other keys as message metadata.
  # Reply metadata never carries such keys. The match is exact and
  # case-sensitive.
  OPTION_PREFIX = "Mesh-Option-"

  # Metadata keys and values the specification fixes on every message.
  module Wire
    CONTENT_TYPE_KEY = "Content-Type"
    CONTENT_TYPE = "application/x-protobuf"
    GRPC_STATUS_KEY = "Grpc-Status"

    # Metadata for a message carrying a payload of the method's type.
    def self.metadata(extra = {})
      extra.to_h.merge(CONTENT_TYPE_KEY => CONTENT_TYPE)
    end

    # Splits +metadata+ into the message metadata and the transport options:
    # the keys that start with OPTION_PREFIX become options with the prefix
    # removed. Returns [metadata, options], both new Hashes.
    def self.split_options(metadata)
      options = {}
      rest = {}
      metadata.to_h.each do |key, value|
        if key.to_s.start_with?(OPTION_PREFIX)
          options[key.to_s.delete_prefix(OPTION_PREFIX)] = value
        else
          rest[key] = value
        end
      end
      [rest, options]
    end

    # A copy of +metadata+ without the keys that start with OPTION_PREFIX.
    def self.without_options(metadata)
      split_options(metadata).first
    end

    # Metadata for a reply whose payload is an encoded google.rpc.Status.
    def self.status_metadata(error, extra = {})
      extra.to_h.merge(CONTENT_TYPE_KEY => CONTENT_TYPE, GRPC_STATUS_KEY => error.proto.code.to_s)
    end
  end
end
