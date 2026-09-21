# frozen_string_literal: true

module GrpcServiceMesh
  # Base of every generated service class. The generated subclass declares its
  # rpcs; the application subclasses that and defines a method per rpc it
  # serves, taking the decoded request and the inbound metadata Hash.
  class RPCService
    extend RpcDSL

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
        response = public_send(rpc.name, rpc.input.decode(message.payload), message.metadata)
        unless response.is_a?(rpc.output)
          raise TypeError, "#{rpc.name} returned #{response.class}, expected #{rpc.output}"
        end

        ServiceMesh::Message.new(target: message.target, metadata: Wire.metadata, payload: response.to_proto)
      rescue MeshError => e
        status_reply(message, e)
      rescue => e
        status_reply(message, MeshError.new(:UNKNOWN, e.message))
      end
    end

    def subscriber_handler(rpc)
      lambda do |message|
        public_send(rpc.name, rpc.input.decode(message.payload), message.metadata)
        nil
      end
    end

    def status_reply(message, error)
      ServiceMesh::Message.new(target: message.target, metadata: Wire.status_metadata(error), payload: error.proto.to_proto)
    end
  end
end
