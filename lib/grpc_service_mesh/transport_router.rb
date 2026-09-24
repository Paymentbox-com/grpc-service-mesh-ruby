# frozen_string_literal: true

module GrpcServiceMesh
  # Holds one entry per transport name and hands out the Client for each.
  # The process router is GrpcServiceMesh.transport_router. Entries are added
  # at boot; client is a hash read.
  class TransportRouter
    # One configured transport. +client+ is the transport's Client the
    # application built and owns, +config+ the runtime configuration, and
    # +runtime+ is ->(client, config, endpoints:, subscribers:) returning the
    # transport's Runtime.
    Transport = Data.define(:client, :config, :runtime)

    def initialize
      @transports = {}
    end

    # Adds a transport. Adding under a name already present replaces the entry.
    def add(name, client:, config:, runtime:)
      @transports[name] = Transport.new(client: client, config: config.to_h, runtime: runtime)
      nil
    end

    # The Transport entry for +name+. Raises UnknownTransport.
    def fetch(name)
      @transports.fetch(name) { raise UnknownTransport.new(name) }
    end

    def names
      @transports.keys
    end

    # The Client for +name+. Raises UnknownTransport.
    def client(name)
      fetch(name).client
    end

    # Closes every entry's client.
    def close
      @transports.each_value { |transport| transport.client.close }
      nil
    end
  end
end
