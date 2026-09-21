# frozen_string_literal: true

require "google/protobuf"
require "google/protobuf/well_known_types"
require "google/rpc/code_pb"
require "google/rpc/status_pb"
require "google/rpc/error_details_pb"

module GrpcServiceMesh
  # The application error. A ROUTE handler raises it; the caller rescues it.
  # It wraps a google.rpc.Status.
  class MeshError < StandardError
    attr_reader :proto

    # Wraps an existing Google::Rpc::Status.
    def self.from_proto(status)
      new(status.code, status.message, *status.details)
    end

    # +code+ is a Google::Rpc::Code name (:NOT_FOUND) or number (5).
    # +details+ are protobuf messages, packed into Google::Protobuf::Any,
    # or Any values already packed.
    def initialize(code, message, *details)
      text = message.to_s
      @proto = Google::Rpc::Status.new(
        code: self.class.code_number(code),
        message: text,
        details: details.map { |d| d.is_a?(Google::Protobuf::Any) ? d : Google::Protobuf::Any.pack(d) }
      )
      super(text)
    end

    # The Google::Rpc::Code name, or the number when it has no name.
    def code
      Google::Rpc::Code.lookup(@proto.code) || @proto.code
    end

    # The wrapped Status's details, as Google::Protobuf::Any values.
    def details
      @proto.details.to_a
    end

    def self.code_number(code)
      case code
      when Integer then code
      when Symbol
        Google::Rpc::Code.resolve(code) or raise ArgumentError, "unknown Google::Rpc::Code #{code.inspect}"
      else
        raise ArgumentError, "code must be a Google::Rpc::Code name or number, got #{code.inspect}"
      end
    end
  end
end
