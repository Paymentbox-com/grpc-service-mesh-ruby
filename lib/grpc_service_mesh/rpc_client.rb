# frozen_string_literal: true

module GrpcServiceMesh
  # Base of every generated client class. Each declared rpc becomes a class
  # method +name(request, metadata: {}, options: {})+ that resolves the
  # transport's Client through the process router on every call.
  class RPCClient
    extend RpcDSL

    class << self
      private

      def define_rpc(rpc)
        define_singleton_method(rpc.name) do |request, metadata: {}, options: {}|
          rpc.route? ? RPCClient.request(rpc, request, metadata, options) : RPCClient.publish(rpc, request, metadata, options)
        end
      end
    end

    # Sends +request+ to a route and returns the decoded response. Raises
    # MeshError for a reply carrying Grpc-Status, or INTERNAL when either
    # payload does not decode.
    def self.request(rpc, request, metadata, options)
      reply = client_for(rpc.target).request(outbound(rpc, request, metadata), options.to_h)
      if reply.metadata.key?(Wire::GRPC_STATUS_KEY)
        raise MeshError.from_proto(decode(Google::Rpc::Status, reply.payload))
      end

      decode(rpc.output, reply.payload)
    end

    # Publishes +request+ to a topic. Returns nil.
    def self.publish(rpc, request, metadata, options)
      client_for(rpc.target).publish(outbound(rpc, request, metadata), options.to_h)
      nil
    end

    def self.client_for(target)
      GrpcServiceMesh.transport_router.client(target.metadata["transport"])
    end

    def self.outbound(rpc, request, metadata)
      raise TypeError, "#{rpc.name} takes a #{rpc.input}, got #{request.class}" unless request.is_a?(rpc.input)

      ServiceMesh::Message.new(target: rpc.target, metadata: Wire.metadata(metadata), payload: request.to_proto)
    end

    def self.decode(klass, payload)
      klass.decode(payload)
    rescue Google::Protobuf::ParseError => e
      raise MeshError.new(:INTERNAL, "reply does not decode as #{klass.descriptor.name}: #{e.message}")
    end

    private_class_method :client_for, :outbound, :decode
  end
end
