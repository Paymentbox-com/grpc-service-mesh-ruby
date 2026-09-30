# frozen_string_literal: true

module GrpcServiceMesh
  # Base of every generated service class. The generated subclass declares its
  # rpcs; the application subclasses that and defines a method per rpc it
  # serves, taking the decoded request, whose mesh_metadata is the inbound
  # message metadata. A route method returns the response; the response's
  # mesh_metadata, without keys that start with OPTION_PREFIX, is the reply's
  # metadata. The same holds for a raised MeshError.
  class RPCService
    extend RpcDSL

    # A ServiceMesh::Endpoint for each route rpc this instance implements,
    # with the rpc's consumer_group in its metadata when it has one.
    def endpoints
      implemented.select(&:route?).map do |rpc|
        ServiceMesh::Endpoint.new(target: rpc.target, handler: endpoint_handler(rpc), metadata: consumer_group_metadata(rpc))
      end
    end

    # A ServiceMesh::Subscriber for each topic rpc this instance implements,
    # with the rpc's consumer_group in its metadata when it has one.
    def subscribers
      implemented.reject(&:route?).map do |rpc|
        ServiceMesh::Subscriber.new(target: rpc.target, handler: subscriber_handler(rpc), metadata: consumer_group_metadata(rpc))
      end
    end

    private

    def consumer_group_metadata(rpc)
      rpc.consumer_group.nil? ? {} : {ServiceMesh::CONSUMER_GROUP_KEY => rpc.consumer_group}
    end

    # Rpcs whose method is defined in the declaring class or below it.
    def implemented
      self.class.rpcs.values.select do |rpc|
        self.class.method_defined?(rpc.name) && self.class.instance_method(rpc.name).owner <= rpc.owner
      end
    end

    def endpoint_handler(rpc)
      lambda do |message|
        request = begin
          decode_inbound(rpc, message)
        rescue Google::Protobuf::ParseError => e
          next status_reply(message, MeshError.new(:INTERNAL, e.message))
        end

        response = public_send(rpc.name, request)
        unless response.is_a?(rpc.output)
          raise TypeError, "#{rpc.name} returned #{response.class}, expected #{rpc.output}"
        end

        metadata = Wire.metadata(Wire.without_options(response.mesh_metadata).except(Wire::GRPC_STATUS_KEY))
        ServiceMesh::Message.new(target: message.target, metadata: metadata, payload: response.to_proto)
      rescue MeshError => e
        status_reply(message, e)
      rescue => e
        status_reply(message, MeshError.new(:UNKNOWN, e.message))
      end
    end

    def subscriber_handler(rpc)
      lambda do |message|
        public_send(rpc.name, decode_inbound(rpc, message))
        nil
      end
    end

    # The decoded payload carrying the message's metadata. A payload that
    # does not decode raises Google::Protobuf::ParseError naming the input
    # type.
    def decode_inbound(rpc, message)
      request = begin
        rpc.input.decode(message.payload)
      rescue Google::Protobuf::ParseError => e
        raise Google::Protobuf::ParseError, "request does not decode as #{rpc.input.descriptor.name}: #{e.message}"
      end
      request.mesh_metadata = message.metadata
      request
    end

    def status_reply(message, error)
      ServiceMesh::Message.new(target: message.target, metadata: Wire.status_metadata(error, Wire.without_options(error.mesh_metadata)), payload: error.proto.to_proto)
    end
  end
end
