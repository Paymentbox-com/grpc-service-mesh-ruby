# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::Metadata do
  it "stores a new empty Hash on first read, so keys can be written into it" do
    order = Shop::Order.new

    order.mesh_metadata["Cache-Control"] = "no-store"

    expect(order.mesh_metadata).to eq({"Cache-Control" => "no-store"})
  end

  it "returns a frozen empty Hash for a frozen object with none set" do
    order = Shop::Order.new.freeze

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
