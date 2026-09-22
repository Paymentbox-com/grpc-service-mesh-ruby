# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::MeshError do
  it "is a StandardError built from a code name and a message" do
    error = described_class.new(:NOT_FOUND, "no such key")

    expect(error).to be_a(StandardError)
    expect(error.code).to eq(:NOT_FOUND)
    expect(error.message).to eq("no such key")
    expect(error.to_s).to eq("no such key")
    expect(error.details).to eq([])
    expect(error.proto).to eq(Google::Rpc::Status.new(code: 5, message: "no such key"))
  end

  it "builds the subclass for a named code" do
    error = described_class.new(:NOT_FOUND, "no such key")

    expect(error).to be_an_instance_of(GrpcServiceMesh::NotFoundError)
    expect(error.code).to eq(:NOT_FOUND)
  end

  it "builds the subclass from a proto" do
    error = described_class.from_proto(Google::Rpc::Status.new(code: 7, message: "nope"))

    expect(error).to be_an_instance_of(GrpcServiceMesh::PermissionDeniedError)
    expect(error.message).to eq("nope")
  end

  it "stays a MeshError for OK and for a number with no name" do
    expect(described_class.new(0, "fine")).to be_an_instance_of(described_class)
    expect(described_class.new(99, "vendor code")).to be_an_instance_of(described_class)
  end

  it "builds a subclass directly from a message and details" do
    info = Google::Rpc::ErrorInfo.new(reason: "KEY_MISSING")

    error = GrpcServiceMesh::NotFoundError.new("no such key", info)

    expect(error).to be_a(described_class)
    expect(error.code).to eq(:NOT_FOUND)
    expect(error.message).to eq("no such key")
    expect(error.details[0].unpack(Google::Rpc::ErrorInfo)).to eq(info)
  end

  it "gives every subclass its own code" do
    expect(GrpcServiceMesh::CancelledError.new("").code).to eq(:CANCELLED)
    expect(GrpcServiceMesh::UnknownError.new("").code).to eq(:UNKNOWN)
    expect(GrpcServiceMesh::InvalidArgumentError.new("").code).to eq(:INVALID_ARGUMENT)
    expect(GrpcServiceMesh::DeadlineExceededError.new("").code).to eq(:DEADLINE_EXCEEDED)
    expect(GrpcServiceMesh::NotFoundError.new("").code).to eq(:NOT_FOUND)
    expect(GrpcServiceMesh::AlreadyExistsError.new("").code).to eq(:ALREADY_EXISTS)
    expect(GrpcServiceMesh::PermissionDeniedError.new("").code).to eq(:PERMISSION_DENIED)
    expect(GrpcServiceMesh::UnauthenticatedError.new("").code).to eq(:UNAUTHENTICATED)
    expect(GrpcServiceMesh::ResourceExhaustedError.new("").code).to eq(:RESOURCE_EXHAUSTED)
    expect(GrpcServiceMesh::FailedPreconditionError.new("").code).to eq(:FAILED_PRECONDITION)
    expect(GrpcServiceMesh::AbortedError.new("").code).to eq(:ABORTED)
    expect(GrpcServiceMesh::OutOfRangeError.new("").code).to eq(:OUT_OF_RANGE)
    expect(GrpcServiceMesh::UnimplementedError.new("").code).to eq(:UNIMPLEMENTED)
    expect(GrpcServiceMesh::InternalError.new("").code).to eq(:INTERNAL)
    expect(GrpcServiceMesh::UnavailableError.new("").code).to eq(:UNAVAILABLE)
    expect(GrpcServiceMesh::DataLossError.new("").code).to eq(:DATA_LOSS)
  end

  it "accepts the code as a number" do
    error = described_class.new(5, "no such key")

    expect(error.code).to eq(:NOT_FOUND)
    expect(error.proto.code).to eq(5)
  end

  it "keeps a number that names no Google::Rpc::Code" do
    error = described_class.new(99, "vendor code")

    expect(error.code).to eq(99)
    expect(error.proto.code).to eq(99)
  end

  it "rejects a name that is not a Google::Rpc::Code" do
    expect { described_class.new(:MISSING, "x") }.to raise_error(ArgumentError, /MISSING/)
  end

  it "rejects a code that is neither a name nor a number" do
    expect { described_class.new("5", "x") }.to raise_error(ArgumentError, /"5"/)
  end

  it "packs detail messages and round-trips them through proto and from_proto" do
    info = Google::Rpc::ErrorInfo.new(reason: "KEY_REVOKED", domain: "pbx", metadata: {"key" => "k1"})
    packed = Google::Protobuf::Any.pack(Google::Rpc::RetryInfo.new)

    error = described_class.new(:FAILED_PRECONDITION, "revoked", info, packed)
    again = described_class.from_proto(Google::Rpc::Status.decode(error.proto.to_proto))

    expect(error.details.map(&:type_name)).to eq(%w[google.rpc.ErrorInfo google.rpc.RetryInfo])
    expect(error.details[1]).to equal(packed)
    expect(again.code).to eq(:FAILED_PRECONDITION)
    expect(again.message).to eq("revoked")
    expect(again.details[0].unpack(Google::Rpc::ErrorInfo)).to eq(info)
    expect(again.details[1].is(Google::Rpc::RetryInfo)).to be(true)
    expect(again.proto).to eq(error.proto)
  end
end
