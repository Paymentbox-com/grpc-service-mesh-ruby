# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::Metadata do
  it "returns a frozen empty Hash when none is set" do
    order = Shop::Order.new

    expect(order.mesh_metadata).to eq({})
    expect(order.mesh_metadata).to be_frozen
  end

  it "returns the Hash it is set to" do
    order = Shop::Order.new

    order.mesh_metadata = {"Request-Id" => "r1"}

    expect(order.mesh_metadata).to eq({"Request-Id" => "r1"})
  end

  it "takes nil as no metadata" do
    order = Shop::Order.new
    order.mesh_metadata = {"Request-Id" => "r1"}

    order.mesh_metadata = nil

    expect(order.mesh_metadata).to eq({})
  end

  it "rejects a value that is not a Hash" do
    order = Shop::Order.new

    expect { order.mesh_metadata = "Request-Id: r1" }.to raise_error(TypeError, /String/)
  end
end
