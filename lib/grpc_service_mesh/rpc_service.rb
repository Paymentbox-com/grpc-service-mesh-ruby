# frozen_string_literal: true

module GrpcServiceMesh
  # Base of every generated service class. The generated subclass declares its
  # rpcs; the application subclasses that and defines a method per rpc it
  # serves, taking the decoded request and the inbound metadata Hash.
  class RPCService
    extend RpcDSL

    # The fiber-local key holding the reply metadata of the running route
    # handler, which GrpcServiceMesh.set_reply_metadata merges into.
    REPLY_METADATA_KEY = :grpc_service_mesh_reply_metadata

    # A ServiceMesh::Endpoint for each route rpc this instance implements.
    def endpoints
      implemented.select(&:route?).map { |rpc| ServiceMesh::Endpoint.new(target: rpc.target, handler: endpoint_handler(rpc)) }
    end

    # A ServiceMesh::Subscriber for each topic rpc this instance implements.
    def subscribers
      implemented.reject(&:route?).map { |rpc| ServiceMesh::Subscriber.new(target: rpc.target, handler: subscriber_handler(rpc)) }
    end

    private

    # Rpcs whose method is defined in the declaring class or below it.
    def implemented
      self.class.rpcs.values.select do |rpc|
        self.class.method_defined?(rpc.name) && self.class.instance_method(rpc.name).owner <= rpc.owner
      end
    end

    def endpoint_handler(rpc)
      lambda do |message|
        outer = Thread.current[REPLY_METADATA_KEY]
        reply_metadata = Thread.current[REPLY_METADATA_KEY] = {}
        response = public_send(rpc.name, rpc.input.decode(message.payload), message.metadata)
        unless response.is_a?(rpc.output)
          raise TypeError, "#{rpc.name} returned #{response.class}, expected #{rpc.output}"
        end

        metadata = Wire.metadata(reply_metadata.except(Wire::GRPC_STATUS_KEY))
        ServiceMesh::Message.new(target: message.target, metadata: metadata, payload: response.to_proto)
      rescue MeshError => e
        status_reply(message, e, reply_metadata)
      rescue => e
        status_reply(message, MeshError.new(:UNKNOWN, e.message), reply_metadata)
      ensure
        Thread.current[REPLY_METADATA_KEY] = outer
      end
    end

    def subscriber_handler(rpc)
      lambda do |message|
        public_send(rpc.name, rpc.input.decode(message.payload), message.metadata)
        nil
      end
    end

    def status_reply(message, error, reply_metadata)
      ServiceMesh::Message.new(target: message.target, metadata: Wire.status_metadata(error, reply_metadata), payload: error.proto.to_proto)
    end
  end
end
