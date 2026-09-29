# Setup

A process that uses this library sets it up at boot, in three steps. It adds
one transport `Client` per transport name to the process router, registers the
services it implements, and builds and starts one `RPCRuntime` per transport
and deployment group it serves. A process that only calls needs only the first
step.

## Configuring the TransportRouter at Boot

`GrpcServiceMesh.transport_router` is the process-wide router. It holds one
`Client` per transport name. The application builds one transport `Client`
per transport name its definitions use, with the transport's configuration and
the generated `ServiceMap` for that transport, and adds it under that name.
The transport gem is a dependency of the application, not of this library.

```ruby
require "grpc_service_mesh"
require "service_maps"

# client is the transport's Client, built from its configuration and ServiceMaps::MEM.
GrpcServiceMesh.add_transport("mem", client)
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

The application implements a generated `RPCService` as described under
[Handlers](handlers.md), and registers an instance in
`GrpcServiceMesh.registry`. Each rpc method it implements becomes a Service
Mesh API `Endpoint` or `Subscriber`, which an `RPCRuntime` passes to the
transport's `Runtime`. An rpc method the subclass does not define is not
served.

```ruby
GrpcServiceMesh.register(Orders.new(db_model, logger))
```

The registry keeps every endpoint and subscriber registered with it. If two
registered services serve the same `Target`, the transport is given two
endpoints or subscribers for it.

## Constructing and Starting an RPCRuntime

`RPCRuntime.new(transport:, deployment_group:, runtime:, config: {})` builds
the runtime for one transport and one deployment group.

It takes the transport's `Client` from `transport_router`. It takes the
`Endpoints` and `Subscribers` whose `Targets` carry `deployment_group` from
`registry`. It copies `config:` and sets `"deployment_group"` in the copy to
`deployment_group:`, overwriting any value `config:` has, and leaves the given
Hash unchanged. It then calls `runtime:` with the client, the copied
configuration, and the endpoints and subscribers, so the transport's runtime is
built in the constructor and `t_runtime` is set before `start`.

`runtime:` is a lambda, `->(client, config, endpoints:, subscribers:)`, that
returns the transport's `Runtime`, built from the client the router passes to
it, which is the one added under the transport's name.

Services registered after the constructor has run are not served.

```ruby
runtime = GrpcServiceMesh::RPCRuntime.new(transport: "mem", deployment_group: "shop", config: {}, runtime: build_runtime)
# raises a library error, or whatever build_runtime raises
runtime.start # raises the transport's error

stop = Queue.new
%w[INT TERM].each { |sig| Signal.trap(sig) { stop << sig } }
stop.pop

runtime.stop(10)
```

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
GrpcServiceMesh::RPCRuntime.new(transport: "mem", deployment_group: "shop", runtime: build_runtime,
  endpoints: Orders.new(db_model, logger).endpoints)
```

`start`, `stop(drain)`, `running?`, and `client` delegate to the underlying
transport runtime, which `t_runtime` returns.

`stop` closes the client. The transport documents what its runtime does,
including what `stop` returns and how it treats a subscriber handler that
raises.

`transport` and `deployment_group` return the transport and deployment group
the `RPCRuntime` was built for.
