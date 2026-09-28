# frozen_string_literal: true

module GrpcServiceMesh
  # Base of every generated client class. Each declared rpc becomes a class
  # method, +name(request, options: {})+, that resolves the transport's Client
  # through the process router on every call. The outbound message metadata is
  # the request's mesh_metadata.
  class RPCClient
    extend RpcDSL

    class << self
      private

      def define_rpc(rpc)
        if rpc.route?
          define_singleton_method(rpc.name) do |request, options: {}|
            RPCClient.request(rpc, request, options)
          end
        else
          define_singleton_method(rpc.name) do |request, options: {}|
            RPCClient.publish(rpc, request, options)
          end
        end
      end
    end

    # Sends +request+ to a route and returns the decoded response, whose
    # mesh_metadata is the reply's metadata. Raises MeshError for a reply
    # carrying Grpc-Status, or INTERNAL when either payload does not decode;
    # either error's mesh_metadata is the reply's metadata.
    def self.request(rpc, request, options)
      reply = client_for(rpc.target).request(outbound(rpc, request), options.to_h)
      reply_metadata = reply.metadata.to_h
      begin
        if reply_metadata.key?(Wire::GRPC_STATUS_KEY)
          raise MeshError.from_proto(decode(Google::Rpc::Status, reply.payload))
        end

        response = decode(rpc.output, reply.payload)
      rescue MeshError => e
        e.mesh_metadata = reply_metadata
        raise
      end
      response.mesh_metadata = reply_metadata
      response
    end

    # Publishes +request+ to a topic. Returns nil.
    def self.publish(rpc, request, options)
      client_for(rpc.target).publish(outbound(rpc, request), options.to_h)
      nil
    end

    def self.client_for(target)
      GrpcServiceMesh.transport_router.client(target.metadata["transport"])
    end

    def self.outbound(rpc, request)
      raise TypeError, "#{rpc.name} takes a #{rpc.input}, got #{request.class}" unless request.is_a?(rpc.input)

      ServiceMesh::Message.new(target: rpc.target, metadata: Wire.metadata(request.mesh_metadata), payload: request.to_proto)
    end

    def self.decode(klass, payload)
      klass.decode(payload)
    rescue Google::Protobuf::ParseError => e
      raise MeshError.new(:INTERNAL, "reply does not decode as #{klass.descriptor.name}: #{e.message}")
    end

    private_class_method :client_for, :outbound, :decode
  end
end
