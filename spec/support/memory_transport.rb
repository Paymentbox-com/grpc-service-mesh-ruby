# frozen_string_literal: true

# An in-process transport for the specs. Runtimes and clients built on one
# Bus deliver to each other directly and record what they were given.
module MemoryTransport
  # This transport's own error, raised by request when nothing serves the target.
  class NoReceiver < StandardError; end

  class Bus
    def initialize
      @lock = Mutex.new
      @endpoints = {}
      @subscribers = {}
    end

    def bind(endpoints, subscribers)
      @lock.synchronize do
        endpoints.each { |e| @endpoints[e.target.segments] = e }
        subscribers.each { |s| (@subscribers[s.target.segments] ||= []) << s }
      end
    end

    def unbind(endpoints, subscribers)
      @lock.synchronize do
        endpoints.each { |e| @endpoints.delete(e.target.segments) }
        subscribers.each { |s| @subscribers[s.target.segments]&.delete(s) }
      end
    end

    def request(message)
      endpoint = @lock.synchronize { @endpoints[message.target.segments] }
      raise NoReceiver, message.target.segments.join(".") unless endpoint

      endpoint.handler.call(message)
    end

    def publish(message)
      @lock.synchronize { (@subscribers[message.target.segments] || []).dup }.each { |s| s.handler.call(message) }
    end
  end

  class Client
    attr_reader :config, :service_map, :bus, :requests, :publishes

    def initialize(config, service_map, bus)
      @config = config
      @service_map = service_map
      @bus = bus
      @requests = []
      @publishes = []
    end

    def request(message, opts = {})
      raise ServiceMesh::KindMismatch, "request needs a route target" unless message.target.kind == :route

      @requests << [message, opts]
      @bus.request(message)
    end

    def publish(message, opts = {})
      raise ServiceMesh::KindMismatch, "publish needs a topic target" unless message.target.kind == :topic

      @publishes << [message, opts]
      @bus.publish(message)
      nil
    end

    def close
      @closed = true
    end

    def closed?
      @closed == true
    end
  end

  class Runtime
    attr_reader :client, :config, :endpoints, :subscribers, :starts, :stops

    # Binds on the given client's bus. stop closes the client.
    def initialize(client, config, endpoints: [], subscribers: [])
      raise ServiceMesh::NoDeploymentGroup if config[ServiceMesh::DEPLOYMENT_GROUP_KEY].to_s.empty?
      raise ServiceMesh::KindMismatch, "endpoint on a topic" if endpoints.any? { |e| e.target.kind != :route }
      raise ServiceMesh::KindMismatch, "subscriber on a route" if subscribers.any? { |s| s.target.kind != :topic }

      @client = client
      @config = config
      @endpoints = endpoints
      @subscribers = subscribers
      @starts = 0
      @stops = []
      @running = false
    end

    def service_map = @client.service_map

    def start
      @client.bus.bind(@endpoints, @subscribers)
      @starts += 1
      @running = true
      nil
    end

    def stop(drain)
      @stops << drain
      @client.bus.unbind(@endpoints, @subscribers)
      @running = false
      @client.close
      true
    end

    def running?
      @running
    end
  end

  # The runtime lambda GrpcServiceMesh.add_transport takes.
  def self.runtime_lambda
    ->(client, config, endpoints:, subscribers:) { Runtime.new(client, config, endpoints: endpoints, subscribers: subscribers) }
  end
end

# A client whose request and publish run the given block and record the call.
# The block receives the message and options and returns the reply.
class RecordingClient
  attr_reader :requests, :publishes

  def initialize(&on_call)
    @on_call = on_call
    @requests = []
    @publishes = []
  end

  def request(message, opts = {})
    @requests << [message, opts]
    @on_call.call(message, opts)
  end

  def publish(message, opts = {})
    @publishes << [message, opts]
    @on_call.call(message, opts)
    nil
  end
end
