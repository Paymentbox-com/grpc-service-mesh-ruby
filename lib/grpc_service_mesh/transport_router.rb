# frozen_string_literal: true

module GrpcServiceMesh
  # Holds one entry per transport name and hands out the Client for each.
  # The process router is GrpcServiceMesh.transport_router.
  class TransportRouter
    # One configured transport. +runtime+ is ->(config, service_map, endpoints:, subscribers:)
    # and +client+ is ->(config, service_map); each returns the transport's
    # Runtime or Client.
    Transport = Data.define(:config, :service_map, :runtime, :client)

    def initialize
      @lock = Mutex.new
      @transports = {}
      @clients = {}
      @runtimes = {}
    end

    # Adds a transport. Adding under a name already present replaces the
    # entry, including any runtime and standalone client recorded under it.
    def add(name, config:, service_map:, runtime:, client:)
      @lock.synchronize do
        @transports[name] = Transport.new(config: config.to_h, service_map: service_map, runtime: runtime, client: client)
        @clients.delete(name)
        @runtimes.delete(name)
      end
      nil
    end

    # The Transport entry for +name+. Raises UnknownTransport.
    def fetch(name)
      @lock.synchronize { @transports.fetch(name) { raise UnknownTransport.new(name) } }
    end

    def names
      @lock.synchronize { @transports.keys }
    end

    # The Client for +name+: the RPCRuntime's client once one exists for
    # this transport, else a standalone client built once from the entry's
    # client lambda and kept. Raises UnknownTransport.
    def client(name)
      @lock.synchronize do
        transport = @transports.fetch(name) { raise UnknownTransport.new(name) }
        rpc_runtime = @runtimes[name]
        next rpc_runtime.client if rpc_runtime

        @clients[name] ||= transport.client.call(transport.config, transport.service_map)
      end
    end

    # Records +rpc_runtime+ as the runtime whose client the router hands out
    # for +name+. The newest runtime attached for a name is the one used.
    def attach_runtime(name, rpc_runtime)
      @lock.synchronize { @runtimes[name] = rpc_runtime }
      nil
    end

    # Closes every standalone client the router has built and forgets them,
    # so a later client call builds a new one. A client shared with an
    # RPCRuntime belongs to that runtime and is released by its stop.
    def close
      @lock.synchronize do
        @clients.each_value(&:close)
        @clients.clear
      end
      nil
    end

    # The RPCRuntime attached for +name+, or nil.
    def runtime(name)
      @lock.synchronize { @runtimes[name] }
    end
  end
end
