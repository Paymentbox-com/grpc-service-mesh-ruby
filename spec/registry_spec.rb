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
      rpc :create, target: target, input: Pbx::ApiKey, output: Pbx::ApiKey, kind: :route
      def create(request, metadata) = request
    end
  end

  let(:api_keys) do
    Class.new(Pbx::ApiKeyService) do
      def search(request, metadata) = request

      def created(request, metadata)
      end
    end
  end

  it "hands back the bindings of one deployment group" do
    GrpcServiceMesh.register(api_keys.new)
    GrpcServiceMesh.register(billing_service.new)

    expect(registry.endpoints("pbx").map(&:target)).to eq([Pbx::ApiKeyTargets::SEARCH])
    expect(registry.subscribers("pbx").map(&:target)).to eq([Pbx::ApiKeyTargets::CREATED])
    expect(registry.endpoints("billing").map(&:target)).to eq([billing_target])
    expect(registry.subscribers("billing")).to eq([])
    expect(registry.endpoints("audit")).to eq([])
  end
end
