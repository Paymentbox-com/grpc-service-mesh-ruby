# frozen_string_literal: true

require "google/protobuf"
require "google/protobuf/well_known_types"
require "google/rpc/code_pb"
require "google/rpc/status_pb"
require "google/rpc/error_details_pb"

module GrpcServiceMesh
  # The application error. A ROUTE handler raises it; the caller rescues it.
  # It wraps a google.rpc.Status and carries the message metadata of the
  # reply that reports it.
  class MeshError < StandardError
    include Metadata

    attr_reader :proto

    # MeshError.new(code, message, *details, mesh_metadata: {}). Returns the
    # subclass for the code when one exists; a subclass called directly takes
    # (message, *details, mesh_metadata: {}) and builds itself.
    def self.new(*args, mesh_metadata: {})
      if equal?(MeshError)
        unless args.first.is_a?(Symbol) || args.first.is_a?(Integer)
          raise ArgumentError, "MeshError.new takes a Google::Rpc::Code first, such as MeshError.new(:NOT_FOUND, \"no such order\"); " \
            "UnknownError.new(message) raises an UNKNOWN error"
        end
        klass = BY_CODE[code_number(args.first)]
        return klass.new(*args.drop(1), mesh_metadata: mesh_metadata) if klass
      end
      super
    end

    # What +raise Klass, "msg"+ calls; builds the error as new does.
    def self.exception(*args, **kwargs)
      new(*args, **kwargs)
    end

    # Wraps an existing Google::Rpc::Status.
    def self.from_proto(status)
      new(status.code, status.message, *status.details)
    end

    # +code+ is a Google::Rpc::Code name (:NOT_FOUND) or number (5).
    # +details+ are protobuf messages, packed into Google::Protobuf::Any,
    # or Any values already packed. +mesh_metadata+ is the metadata the
    # error reply carries.
    def initialize(code, message, *details, mesh_metadata: {})
      text = message.to_s
      @proto = Google::Rpc::Status.new(
        code: self.class.code_number(code),
        message: text,
        details: details.map { |d| pack(d) }
      )
      self.mesh_metadata = mesh_metadata
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

    private def pack(detail)
      return detail if detail.is_a?(Google::Protobuf::Any)
      unless detail.class.respond_to?(:descriptor)
        raise TypeError, "a detail must be a protobuf message, got #{detail.class}"
      end

      Google::Protobuf::Any.pack(detail)
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

      def self.new(message, *details, mesh_metadata: {})
        super(self::CODE, message, *details, mesh_metadata: mesh_metadata)
      end
    end
    const_set(name, klass)
  end

  MeshError::BY_CODE = MeshError.subclasses.to_h { |k| [MeshError.code_number(k::CODE), k] }.freeze
end
