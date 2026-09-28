# frozen_string_literal: true

RSpec.describe GrpcServiceMesh::RPCClient do
  # Routes "nats" to a RecordingClient running the block.
  def transport_client(&on_call)
    client = RecordingClient.new(&on_call)
    GrpcServiceMesh.add_transport("nats", client)
    client
  end

  def reply(metadata, payload)
    ServiceMesh::Message.new(target: Shop::OrderTargets::PLACE, metadata: metadata, payload: payload)
  end

  def order(metadata = {}, **fields)
    order = Shop::Order.new(**fields)
    order.mesh_metadata = metadata
    order
  end

  describe "a route method" do
    it "sends the encoded request with its metadata and the options to the target's transport and decodes the reply" do
      response = Shop::Order.new(id: "O-1")
      client = transport_client { reply({"Content-Type" => "application/x-protobuf", "Request-Id" => "r1"}, response.to_proto) }
      request = order({"Request-Id" => "r1"}, id: "o-1")

      result = Shop::OrderClient.place(request, options: {"request_timeout" => "2"})

      expect(result).to eq(response)
      expect(result.mesh_metadata).to eq({"Content-Type" => "application/x-protobuf", "Request-Id" => "r1"})
      message, options = client.requests.first
      expect(client.requests.size).to eq(1)
      expect(message.target).to eq(Shop::OrderTargets::PLACE)
      expect(message.metadata).to eq({"Request-Id" => "r1", "Content-Type" => "application/x-protobuf"})
      expect(Shop::Order.decode(message.payload)).to eq(Shop::Order.new(id: "o-1"))
      expect(options).to eq({"request_timeout" => "2"})
      expect(request.mesh_metadata).to eq({"Request-Id" => "r1"})
    end

    it "sends Content-Type with no request metadata or options" do
      client = transport_client { reply({}, Shop::Order.new.to_proto) }

      Shop::OrderClient.place(Shop::Order.new)

      message, options = client.requests.first
      expect(message.metadata).to eq({"Content-Type" => "application/x-protobuf"})
      expect(options).to eq({})
    end

    it "raises the MeshError a reply with Grpc-Status carries, with the reply's metadata" do
      info = Google::Rpc::ErrorInfo.new(reason: "ORDER_CANCELLED", domain: "shop")
      status = Google::Rpc::Status.new(code: 5, message: "no such order", details: [Google::Protobuf::Any.pack(info)])
      transport_client { reply({"Content-Type" => "application/x-protobuf", "Grpc-Status" => "5", "Retry-After" => "30"}, status.to_proto) }

      expect { Shop::OrderClient.place(Shop::Order.new) }.to raise_error(GrpcServiceMesh::NotFoundError) do |error|
        expect(error.code).to eq(:NOT_FOUND)
        expect(error.message).to eq("no such order")
        expect(error.details.map { |d| d.unpack(Google::Rpc::ErrorInfo) }).to eq([info])
        expect(error.mesh_metadata).to eq({"Content-Type" => "application/x-protobuf", "Grpc-Status" => "5", "Retry-After" => "30"})
      end
    end

    it "raises INTERNAL with the reply's metadata when the response does not decode" do
      transport_client { reply({"Content-Type" => "application/x-protobuf", "Request-Id" => "r1"}, "\x80".b) }

      expect { Shop::OrderClient.place(Shop::Order.new) }.to raise_error(GrpcServiceMesh::MeshError) do |error|
        expect(error.code).to eq(:INTERNAL)
        expect(error.message).to include("shop.Order")
        expect(error.mesh_metadata).to eq({"Content-Type" => "application/x-protobuf", "Request-Id" => "r1"})
      end
    end

    it "raises INTERNAL when the Status does not decode" do
      transport_client { reply({"Grpc-Status" => "5"}, "\x80".b) }

      expect { Shop::OrderClient.place(Shop::Order.new) }.to raise_error(GrpcServiceMesh::MeshError) do |error|
        expect(error.code).to eq(:INTERNAL)
        expect(error.message).to include("google.rpc.Status")
      end
    end

    it "lets a transport error pass through unchanged" do
      transport_client { raise MemoryTransport::NoReceiver, "shop.OrderService.Place" }

      expect { Shop::OrderClient.place(Shop::Order.new) }.to raise_error(MemoryTransport::NoReceiver, "shop.OrderService.Place")
    end

    it "rejects a request of the wrong class before sending" do
      client = transport_client { raise "not reached" }

      expect { Shop::OrderClient.place(Google::Rpc::Status.new) }
        .to raise_error(TypeError, "place takes a Shop::Order, got Google::Rpc::Status")
      expect(client.requests).to eq([])
    end

    it "raises UnknownTransport when the target's transport is not configured" do
      expect { Shop::OrderClient.place(Shop::Order.new) }.to raise_error(GrpcServiceMesh::UnknownTransport, 'unknown transport "nats"')
    end
  end

  describe "a topic method" do
    it "publishes the encoded request with its metadata and the options and returns nil" do
      client = transport_client { nil }

      result = Shop::OrderClient.placed(order({"Event-Id" => "e1"}, id: "o-1"), options: {"flush" => "1"})

      expect(result).to be_nil
      message, options = client.publishes.first
      expect(client.publishes.size).to eq(1)
      expect(message.target).to eq(Shop::OrderTargets::PLACED)
      expect(message.metadata).to eq({"Event-Id" => "e1", "Content-Type" => "application/x-protobuf"})
      expect(Shop::Order.decode(message.payload)).to eq(Shop::Order.new(id: "o-1"))
      expect(options).to eq({"flush" => "1"})
    end

    it "lets a Service Mesh API error pass through unchanged" do
      transport_client { raise ServiceMesh::KindMismatch, "publish needs a topic target" }

      expect { Shop::OrderClient.placed(Shop::Order.new) }.to raise_error(ServiceMesh::KindMismatch, "publish needs a topic target")
    end
  end
end
