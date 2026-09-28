# frozen_string_literal: true

module GrpcServiceMesh
  # Base of every generated client class. Each declared rpc becomes a class
  # method, +name(request)+, that resolves the transport's Client through the
  # process router on every call. The request's mesh_metadata is read and left
  # unchanged: its keys that start with OPTION_PREFIX are the transport
  # options, with the prefix removed, and the other keys are the message
  # metadata.
  class RPCClient
    extend RpcDSL

    class << self
      private

      def define_rpc(rpc)
        if rpc.route?
          define_singleton_method(rpc.name) do |request|
            RPCClient.request(rpc, request)
          end
        else
          define_singleton_method(rpc.name) do |request|
            RPCClient.publish(rpc, request)
          end
        end
      end
    end

    # Sends +request+ to a route and returns the decoded response, whose
    # mesh_metadata is the reply's metadata without keys that start with
    # OPTION_PREFIX. Raises MeshError for a reply carrying Grpc-Status, or
    # INTERNAL when either payload does not decode; either error's
    # mesh_metadata is the same reply metadata.
    def self.request(rpc, request)
      message, options = outbound(rpc, request)
      reply = client_for(rpc.target).request(message, options)
      reply_metadata = Wire.without_options(reply.metadata)
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
    def self.publish(rpc, request)
      message, options = outbound(rpc, request)
      client_for(rpc.target).publish(message, options)
      nil
    end

    def self.client_for(target)
      GrpcServiceMesh.transport_router.client(target.metadata["transport"])
    end

    # The message for +request+ and the transport options, split from the
    # request's mesh_metadata.
    def self.outbound(rpc, request)
      raise TypeError, "#{rpc.name} takes a #{rpc.input}, got #{request.class}" unless request.is_a?(rpc.input)

      metadata, options = Wire.split_options(request.mesh_metadata)
      [ServiceMesh::Message.new(target: rpc.target, metadata: Wire.metadata(metadata), payload: request.to_proto), options]
    end

    def self.decode(klass, payload)
      klass.decode(payload)
    rescue Google::Protobuf::ParseError => e
      raise MeshError.new(:INTERNAL, "reply does not decode as #{klass.descriptor.name}: #{e.message}")
    end

    private_class_method :client_for, :outbound, :decode
  end
end
