# Setup

## Configuring the TransportRouter at Boot

`GrpcServiceMesh.transport_router` is the process-wide router. It holds one
`Client` per transport name. The application builds one transport `Client`
per transport name its definitions use, with the transport's configuration and
the generated `ServiceMap` for that transport, and adds it under that name.
The transport gem is a dependency of the application, not of this library.

```ruby
require "grpc_service_mesh"
require "service_maps"

# client is the transport's Client, built from its configuration and ServiceMaps::NATS.
GrpcServiceMesh.add_transport("nats", client)
```

The application owns each client and the connection it holds. Clients are
added at boot, before any call is made or any `RPCRuntime` is built. Generated
clients and `RPCRuntime` find the process router themselves, so nothing
generated takes a router argument.

`transport_router.client(name)` returns the client the application added under
`name`, and it is what every generated client method on that transport sends
through. `add_transport` under a name already present replaces the client.
Looking up a name that was not added raises `GrpcServiceMesh::UnknownTransport`,
listed under [Library Errors](mesherror.md#library-errors).

A process that only calls builds its clients, adds them, and runs
`transport_router.close` before exit, so each transport sends what it has
buffered. `close` closes every client, even when some of them fail to close. It
returns `nil` when every client closed, and otherwise raises
`GrpcServiceMesh::CloseFailed`, whose `failures` maps each transport name to the
exception its client raised.

An `RPCRuntime` for a transport is built on the router's client for that
transport, and its `stop` closes that client as well.

## Registering a Service

A [generated](generated-code.md) `RPCService` class declares one rpc per `rpc`
method and serves nothing by itself. The application subclasses it, defines a
method for each rpc it serves, and registers an instance in
`GrpcServiceMesh.registry`. Implemented rpcs are turned into Service Mesh API
`Endpoints` and `Subscribers` and passed through to the transport's `Runtime`.
An rpc without a method is excluded.

```ruby
class Orders < Shop::OrderService
  def initialize(store, audit)
    @store = store
    @audit = audit
  end

  def place(request)
    @store.in_stock?(request.item) or raise GrpcServiceMesh::NotFoundError, "no such item"
    Shop::Order.new(id: @store.place(request.item), item: request.item)
  end

  def placed(event)
    @audit.record(event)
  end
end

GrpcServiceMesh.register(Orders.new(store, audit))
```

A service instance serves every rpc whose method is defined by its class, or by
a superclass below the generated service class.

The registry keeps every endpoint and subscriber registered with it. If two
registered services serve the same `Target`, the transport is given two
endpoints or subscribers for it.

## Constructing and Starting an RPCRuntime

`RPCRuntime.new(transport:, deployment_group:, runtime:, config: {})` takes the
transport's `Client` from `transport_router` and the `Endpoints` and
`Subscribers` whose `Targets` carry `deployment_group` from `registry`, copies
`config` with `"deployment_group"` set to the given `deployment_group`, and
calls `runtime:`.

`runtime:` is a lambda, `->(client, config, endpoints:, subscribers:)`, that
returns the transport's `Runtime`. The transport's runtime is built in the
constructor, so `t_runtime` is set before `start`.

A `"deployment_group"` key in `config:` is overwritten by `deployment_group:`,
and the given Hash itself is left unchanged. Services registered after the
constructor has run are not served.

```ruby
runtime = GrpcServiceMesh::RPCRuntime.new(transport: "nats", deployment_group: "shop", config: {}, runtime: build_runtime)
runtime.start

stop = Queue.new
%w[INT TERM].each { |sig| Signal.trap(sig) { stop << sig } }
stop.pop

runtime.stop(10)
```

In the above example, `build_runtime` is a lambda with the `runtime:` signature
that returns the transport's `Runtime`, built from the client the router passes
to it, which is the one added under `nats`.

`RPCRuntime.new` raises a library error when `runtime:` does not respond to
`call`, when the transport was not added to the router, or when a given
`Target` is outside the runtime. These are listed under
[Library Errors](mesherror.md#library-errors). Whatever `runtime:` raises passes
through unchanged.

`endpoints:` and `subscribers:` give the runtime a list to serve in place of
the registry's list of that kind, so a process can serve only part of a
deployment group. `nil`, the default, takes the list from the registry, and
`[]` serves none of that kind. Every `Target` in a given list must carry the
runtime's `deployment_group` and `transport`.

```ruby
GrpcServiceMesh::RPCRuntime.new(transport: "nats", deployment_group: "shop", runtime: build_runtime,
  endpoints: Orders.new(store, audit).endpoints)
```

`start`, `stop(drain)`, `running?`, and `client` delegate to the underlying
transport runtime, which `t_runtime` returns. `stop` closes the client. The
transport documents what its runtime does, including what `stop` returns and
how it treats a subscriber handler that raises. `transport` and
`deployment_group` return the transport and deployment group the `RPCRuntime`
was built for.
