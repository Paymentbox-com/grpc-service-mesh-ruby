# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::Registry do
  let(:registry) { GrpcServiceMesh.registry }

  let(:billing_target) do
    ServiceMesh::Target.new(segments: %w[billing InvoiceService Create], kind: :route,
      metadata: {"deployment_group" => "billing", "transport" => "http"})
  end

  let(:billing_service) do
    target = billing_target
    Class.new(GrpcServiceMesh::RPCService) do
      rpc :create, target: target, input: Shop::Order, output: Shop::Order, kind: :route
      def create(request, metadata) = request
    end
  end

  let(:orders) do
    Class.new(Shop::OrderService) do
      def place(request, metadata) = request

      def placed(request, metadata)
      end
    end
  end

  it "hands back the bindings of one deployment group" do
    GrpcServiceMesh.register(orders.new)
    GrpcServiceMesh.register(billing_service.new)

    expect(registry.endpoints("shop").map(&:target)).to eq([Shop::OrderTargets::PLACE])
    expect(registry.subscribers("shop").map(&:target)).to eq([Shop::OrderTargets::PLACED])
    expect(registry.endpoints("billing").map(&:target)).to eq([billing_target])
    expect(registry.subscribers("billing")).to eq([])
    expect(registry.endpoints("audit")).to eq([])
  end
end
