# frozen_string_literal: true

module GrpcServiceMesh
  # Base of every generated client class. Each declared rpc becomes a class
  # method that resolves the transport's Client through the process router on
  # every call: +name(request, metadata: {}, options: {}, reply_metadata: nil)+
  # for a route and +name(request, metadata: {}, options: {})+ for a topic.
  class RPCClient
    extend RpcDSL

    class << self
      private

      def define_rpc(rpc)
        if rpc.route?
          define_singleton_method(rpc.name) do |request, metadata: {}, options: {}, reply_metadata: nil|
            RPCClient.request(rpc, request, metadata, options, reply_metadata)
          end
        else
          define_singleton_method(rpc.name) do |request, metadata: {}, options: {}|
            RPCClient.publish(rpc, request, metadata, options)
          end
        end
      end
    end

    # Sends +request+ to a route and returns the decoded response. Raises
    # MeshError for a reply carrying Grpc-Status, or INTERNAL when either
    # payload does not decode. When +reply_metadata+ is a Hash, its contents
    # are replaced with the reply's metadata on every reply that arrives; an
    # error before a reply arrives leaves it unchanged.
    def self.request(rpc, request, metadata, options, reply_metadata)
      unless reply_metadata.nil? || reply_metadata.is_a?(Hash)
        raise TypeError, "reply_metadata: takes a Hash, got #{reply_metadata.class}"
      end

      reply = client_for(rpc.target).request(outbound(rpc, request, metadata), options.to_h)
      reply_metadata&.replace(reply.metadata.to_h)
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
