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

    # Returns the subclass for +code+ when one exists; a subclass called
    # directly builds itself.
    def self.new(code, message, *details)
      if equal?(MeshError)
        klass = BY_CODE[code_number(code)]
        return klass.new(message, *details) if klass
      end
      super
    end

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

  # One subclass per Google::Rpc::Code other than OK, each fixing its code.
  # MeshError.new and from_proto return the subclass for the code.
  {
    CancelledError: :CANCELLED,
    UnknownError: :UNKNOWN,
    InvalidArgumentError: :INVALID_ARGUMENT,
    DeadlineExceededError: :DEADLINE_EXCEEDED,
    NotFoundError: :NOT_FOUND,
    AlreadyExistsError: :ALREADY_EXISTS,
    PermissionDeniedError: :PERMISSION_DENIED,
    UnauthenticatedError: :UNAUTHENTICATED,
    ResourceExhaustedError: :RESOURCE_EXHAUSTED,
    FailedPreconditionError: :FAILED_PRECONDITION,
    AbortedError: :ABORTED,
    OutOfRangeError: :OUT_OF_RANGE,
    UnimplementedError: :UNIMPLEMENTED,
    InternalError: :INTERNAL,
    UnavailableError: :UNAVAILABLE,
    DataLossError: :DATA_LOSS
  }.each do |name, code|
    klass = Class.new(MeshError) do
      const_set(:CODE, code)

      def self.new(message, *details)
        super(self::CODE, message, *details)
      end
    end
    const_set(name, klass)
  end

  MeshError::BY_CODE = MeshError.subclasses.to_h { |k| [MeshError.code_number(k::CODE), k] }.freeze
end
