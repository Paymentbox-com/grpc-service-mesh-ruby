# frozen_string_literal: true

module GrpcServiceMesh
  # Holds one Client per transport name: the transport-specific Client the
  # application built and owns. The process router is
  # GrpcServiceMesh.transport_router. Clients are added at boot; client is a
  # hash read.
  class TransportRouter
    def initialize
      @clients = {}
    end

    # Adds a client. Adding under a name already present replaces the client.
    def add(name, client)
      @clients[name] = client
      nil
    end

    def names
      @clients.keys
    end

    # The Client for +name+. Raises UnknownTransport.
    def client(name)
      @clients.fetch(name) { raise UnknownTransport.new(name) }
    end

    # Closes every client.
    def close
      @clients.each_value(&:close)
      nil
    end
  end
end
