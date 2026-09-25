# frozen_string_literal: true

require "mesh/options_pb"

RSpec.describe "mesh/options_pb" do
  it "loads from this gem's lib directory" do
    path = File.expand_path("../lib/mesh/options_pb.rb", __dir__)

    expect($LOADED_FEATURES).to include(path)
  end

  it "registers the four extensions by full name" do
    pool = Google::Protobuf::DescriptorPool.generated_pool

    kind = pool.lookup("mesh.kind").to_proto
    expect([kind.number, kind.extendee]).to eq([50001, ".google.protobuf.MethodOptions"])
    consumer_group = pool.lookup("mesh.consumer_group").to_proto
    expect([consumer_group.number, consumer_group.extendee]).to eq([50002, ".google.protobuf.MethodOptions"])
    deployment_group = pool.lookup("mesh.deployment_group").to_proto
    expect([deployment_group.number, deployment_group.extendee]).to eq([50003, ".google.protobuf.FileOptions"])
    transport = pool.lookup("mesh.transport").to_proto
    expect([transport.number, transport.extendee]).to eq([50004, ".google.protobuf.FileOptions"])
  end
end
