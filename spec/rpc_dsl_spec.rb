# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::RpcDSL do
  it "records each rpc with its owner and lists inherited ones" do
    parent = Class.new(GrpcServiceMesh::RPCService) do
      rpc :place, target: Shop::OrderTargets::PLACE, input: Shop::Order, output: Shop::Order, kind: :route
    end
    child = Class.new(parent) do
      rpc :placed, target: Shop::OrderTargets::PLACED, input: Shop::Order, kind: :topic
    end

    expect(parent.rpcs.keys).to eq([:place])
    expect(child.rpcs.keys).to eq(%i[place placed])
    expect(child.rpcs[:place]).to eq(GrpcServiceMesh::Rpc.new(
      name: :place, target: Shop::OrderTargets::PLACE, input: Shop::Order, output: Shop::Order, kind: :route, owner: parent
    ))
    expect(child.rpcs[:placed].output).to be_nil
  end

  it "rejects a kind that disagrees with the target" do
    expect {
      Class.new(GrpcServiceMesh::RPCService) do
        rpc :place, target: Shop::OrderTargets::PLACE, input: Shop::Order, output: Shop::Order, kind: :topic
      end
    }.to raise_error(ServiceMesh::KindMismatch, /declared topic, target is route/)
  end
end
