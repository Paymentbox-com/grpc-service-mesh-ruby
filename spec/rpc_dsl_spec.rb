# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::RpcDSL do
  it "records each rpc with its owner and lists inherited ones" do
    parent = Class.new(GrpcServiceMesh::RPCService) do
      rpc :search, target: Pbx::ApiKeyTargets::SEARCH, input: Pbx::ApiKey, output: Pbx::ApiKey, kind: :route
    end
    child = Class.new(parent) do
      rpc :created, target: Pbx::ApiKeyTargets::CREATED, input: Pbx::ApiKey, kind: :topic
    end

    expect(parent.rpcs.keys).to eq([:search])
    expect(child.rpcs.keys).to eq(%i[search created])
    expect(child.rpcs[:search]).to eq(GrpcServiceMesh::Rpc.new(
      name: :search, target: Pbx::ApiKeyTargets::SEARCH, input: Pbx::ApiKey, output: Pbx::ApiKey, kind: :route, owner: parent
    ))
    expect(child.rpcs[:created].output).to be_nil
  end

  it "rejects a kind that disagrees with the target" do
    expect {
      Class.new(GrpcServiceMesh::RPCService) do
        rpc :search, target: Pbx::ApiKeyTargets::SEARCH, input: Pbx::ApiKey, output: Pbx::ApiKey, kind: :topic
      end
    }.to raise_error(ServiceMesh::KindMismatch, /declared topic, target is route/)
  end
end
