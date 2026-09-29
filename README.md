# grpc-service-mesh-ruby

The Ruby library for the
[gRPC Service Mesh API](https://github.com/Paymentbox-com/grpc-service-mesh-api),
packaged as the gem `grpc_service_mesh`, module `GrpcServiceMesh`. The library
provides the non-generated types the specification names, `TransportRouter`,
`Registry`, `RPCRuntime`, and `MeshError`, together with the two base classes
the generator's Ruby output builds on, `RPCService` and `RPCClient`.

The Service Mesh API types and errors come from
[service-mesh-ruby](https://github.com/Paymentbox-com/service-mesh-ruby), gem
`service_mesh`. Transports are separate gems that the application configures at
boot; the NATS one is
[service-mesh-nats-ruby](https://github.com/Paymentbox-com/service-mesh-nats-ruby).

## Install

The gem and its `service_mesh` dependency come from their repositories at a
tag; Bundler needs both git sources in the Gemfile.

```ruby
# Gemfile
gem "grpc_service_mesh", git: "https://github.com/Paymentbox-com/grpc-service-mesh-ruby", tag: "v0.14.0"
gem "service_mesh", git: "https://github.com/Paymentbox-com/service-mesh-ruby", tag: "v0.4.0"
gem "service_mesh_nats", git: "https://github.com/Paymentbox-com/service-mesh-nats-ruby", tag: "v0.5.0" # or another transport
```

Requires Ruby 3.3 or newer. Depends on `service_mesh`, `google-protobuf`, and
`googleapis-common-protos-types`, which provides `Google::Rpc::Status`,
`Google::Rpc::Code`, and the detail types in `google/rpc/error_details.proto`.
No transport is a dependency.

## Usage

The examples use the generated code shown under Generated code: the
`Shop::OrderService`, `Shop::OrderClient`, and `Shop::OrderTargets` produced
from the specification's `examples/shop/order.proto`, and `ServiceMaps::NATS`
produced from every target on the `nats` transport.

### Message metadata

Message metadata travels on the message objects. `GrpcServiceMesh::Metadata`
is a module the generated code includes into every message class an rpc takes
or returns. It adds two methods.

| method | value |
|---|---|
| `#mesh_metadata` | the object's metadata Hash; on first read a new empty Hash stored on the object, so keys can be written into it; a frozen object with none set returns a frozen empty Hash |
| `#mesh_metadata=(hash)` | sets the metadata; `nil` sets none, and a value that is not a Hash raises `TypeError` |

The library sets `mesh_metadata` on the objects it builds, the decoded request
a handler receives and the decoded response or `MeshError` a caller receives.
It reads `mesh_metadata` from the objects the application gives it, the
request a caller sends and the response a handler returns, and never writes to
them, so a handler may return a shared or frozen object. `MeshError` includes
the module too. A message class that declares a field named `mesh_metadata`
cannot carry metadata, and the generator rejects it.

### Configuring the TransportRouter at boot

The process has one `TransportRouter`, `GrpcServiceMesh.transport_router`. It
holds one `Client` per transport name. Each transport the generated code names
is added once, with the transport's `Client` the application built from the
generated `ServiceMap`. Nothing generated takes a router argument; generated
clients and `RPCRuntime` find the process router themselves.

```ruby
require "grpc_service_mesh"
require "service_mesh_nats"
require "service_maps"

client = ServiceMeshNats::Client.new({"url" => ENV.fetch("NATS_URL", "nats://127.0.0.1:4222")}, ServiceMaps::NATS)
GrpcServiceMesh.add_transport("nats", client)
```

The application owns the client and the connection it holds.
`add_transport` under a name already present replaces the client. Clients are
added at boot, before any call or `RPCRuntime`.

`transport_router.client(name)` returns the client added under the name, so a
process that serves and calls over one transport uses one connection. A name
the router does not hold raises `GrpcServiceMesh::UnknownTransport`.
`transport_router.close` closes every added client; a process that only calls
runs it before exit so the transport flushes what it has buffered. In a
process that serves, the `RPCRuntime`'s `stop` closes the client.

### Registering a service

The generated `Shop::OrderService` declares the rpcs of the proto service and
serves nothing itself. The application subclasses it and defines a method for
each rpc it serves. The method takes one argument, the decoded request, whose
`mesh_metadata` is the inbound message metadata. A route method returns the
response message; a topic method's return value is ignored.

```ruby
class Orders < Shop::OrderService
  def initialize(store)
    @store = store
  end

  def place(request)
    @store.in_stock?(request.item) or
      raise GrpcServiceMesh::NotFoundError.new("no item #{request.item}",
        Google::Rpc::ErrorInfo.new(reason: "ITEM_MISSING", domain: "shop", metadata: {"request_id" => request.mesh_metadata["Request-Id"].to_s}))
    Shop::Order.new(id: @store.place(request.item), item: request.item)
  end

  def placed(request)
    @store.record(request)
  end
end

GrpcServiceMesh.register(Orders.new(store))
```

`GrpcServiceMesh.register` takes an instance and adds its `endpoints` and
`subscribers` to the process `Registry`, `GrpcServiceMesh.registry`. A subclass
serves exactly the rpc methods defined in it or below it; an rpc whose method
is missing is not bound. Every registered binding is kept, so two
registrations of one target hand the transport two bindings for it.

#### Reply metadata

The reply's metadata is the `mesh_metadata` of the response a route method
returns. When the method raises a `MeshError`, the reply's metadata is the
error's `mesh_metadata`, which the error takes on construction as
`mesh_metadata:` or through `mesh_metadata=`. The `UNKNOWN` reply for any
other exception carries only the library's keys. The library writes
`Content-Type` and `Grpc-Status` over the application's values, so its own
values win, and a successful reply carries no `Grpc-Status`. Keys that start
with `Mesh-Option-` are dropped from the reply's metadata.

```ruby
def place(request)
  @store.in_stock?(request.item) or
    raise GrpcServiceMesh::NotFoundError.new("no item #{request.item}", mesh_metadata: {"Retry-After" => "30"})
  order = Shop::Order.new(id: @store.place(request.item), item: request.item)
  order.mesh_metadata = {"Request-Id" => request.mesh_metadata["Request-Id"].to_s}
  order
end
```

### Starting an RPCRuntime

An `RPCRuntime` serves one transport and one deployment group. Its
constructor takes the transport's client from the router and the registry's
endpoints and subscribers whose target metadata `deployment_group` matches,
and calls the `runtime:` lambda, `->(client, config, endpoints:, subscribers:)`,
with the client, `config:` merged with `"deployment_group"`, and those
bindings. `config:` defaults to an empty Hash and is left unchanged; a
`"deployment_group"` key in it is overwritten. Services registered after
construction are not served by it. The transport's `Runtime` is built from the
client it is given, so the client generated code resolves through the router
is the runtime's connection.

```ruby
runtime = GrpcServiceMesh::RPCRuntime.new(
  transport: "nats",
  deployment_group: "shop",
  config: {},
  runtime: ->(c, cfg, endpoints:, subscribers:) { ServiceMeshNats::Runtime.new(c, cfg, endpoints: endpoints, subscribers: subscribers) }
)
runtime.start
at_exit { runtime.stop(10) }
```

A `runtime:` that does not respond to `call` raises `ArgumentError`, a name
the router does not hold raises `GrpcServiceMesh::UnknownTransport` from the
constructor, and whatever the `runtime:` lambda raises passes through.

`endpoints:` and `subscribers:` give the runtime a list to serve in place of
the registry's list of that kind, so a process can serve part of a deployment
group. `nil`, the default, takes the list from the registry, and `[]` serves
none of that kind. Every target in a given list must carry the runtime's
`deployment_group` and `transport`; one that does not raises `ArgumentError`
naming its segments and the key that differs.

```ruby
GrpcServiceMesh::RPCRuntime.new(transport: "nats", deployment_group: "shop", runtime: runtime_lambda,
  endpoints: Orders.new(store).endpoints)
```

`start`, `stop(drain)`, `running?`, and `client` delegate to the transport's
`Runtime`, which `t_runtime` exposes. `stop` closes the client. The transport
documents what its runtime does, including what `stop` returns and how it
treats a subscriber handler that raises.

### Calling a service

Generated client methods are class methods, `name(request)`. The call reads
the request's `mesh_metadata` and leaves it unchanged. Every call resolves the
transport's `Client` through the router, so the same code runs in a process
that serves and in one that only calls.

Keys of the request's `mesh_metadata` that start with `Mesh-Option-`
(`GrpcServiceMesh::OPTION_PREFIX`) are transport options. The call removes them
from the outbound message's metadata and passes each one to the transport's
`request` or `publish` options with the prefix removed, so
`"Mesh-Option-request_timeout" => "2"` reaches the transport as option
`"request_timeout" => "2"`. The match is exact and case-sensitive. Every other
key is the outbound message's metadata.

```ruby
request = Shop::Order.new(item: "book")
request.mesh_metadata = {"Request-Id" => SecureRandom.uuid, "Mesh-Option-request_timeout" => "2"}
begin
  order = Shop::OrderClient.place(request)
rescue GrpcServiceMesh::NotFoundError => e
  e.message                # "no item book"
  info = e.details.find { |d| d.is(Google::Rpc::ErrorInfo) }&.unpack(Google::Rpc::ErrorInfo)
rescue GrpcServiceMesh::MeshError => e
  e.code                   # any other Google::Rpc::Code name
rescue NATS::Timeout, NATS::IO::NoRespondersError
  # transport errors pass through unchanged
end

event = Shop::Order.new(id: "o-1", item: "book")
event.mesh_metadata = {"Event-Id" => "e1"}
Shop::OrderClient.placed(event)
```

A route method returns the decoded response. A topic method returns `nil`. A
request that is not an instance of the rpc's input class raises `TypeError`
before anything is sent.

#### Reply metadata

The response a route method returns has `mesh_metadata` set to the reply's
metadata. A `MeshError` raised from a reply, including the `INTERNAL` error for
a payload that does not decode, has `mesh_metadata` set to that reply's
metadata. Keys that start with `Mesh-Option-` are dropped from it in both
cases. An error before a reply arrives, such as a transport error, carries
none.

```ruby
order = Shop::OrderClient.place(Shop::Order.new(item: "book"))
order.mesh_metadata["Request-Id"]
```

## Errors

`GrpcServiceMesh::MeshError` descends from `StandardError` and wraps a
`Google::Rpc::Status`.

| member | value |
|---|---|
| `MeshError.new(code, message, *details, mesh_metadata: {})` | `code` is a `Google::Rpc::Code` name such as `:NOT_FOUND` or its number such as `5`; `details` are protobuf messages, packed into `Google::Protobuf::Any`, or `Any` values already packed; `mesh_metadata:` is the metadata of the reply that reports the error |
| `MeshError.from_proto(status)` | wraps a `Google::Rpc::Status` |
| `#code` | the `Google::Rpc::Code` name, or the number when it has no name |
| `#message` | the text, also what `to_s` returns |
| `#details` | an Array of `Google::Protobuf::Any`; unpack with `any.unpack(klass)`, test with `any.is(klass)` |
| `#proto` | the `Google::Rpc::Status` |
| `#mesh_metadata`, `#mesh_metadata=` | the reply metadata, from `GrpcServiceMesh::Metadata` |

`MeshError` has one subclass per `Google::Rpc::Code` other than `OK`:
`NotFoundError`, `InvalidArgumentError`, `PermissionDeniedError`,
`UnauthenticatedError`, `FailedPreconditionError`, `InternalError`,
`UnavailableError`, and the rest, each named after its code. A subclass is
built from a message, details, and `mesh_metadata:`,
`GrpcServiceMesh::NotFoundError.new("no such order", info)`, and fixes its own
code. `raise GrpcServiceMesh::NotFoundError, "no such order"` builds the same
error with no details, and `raise GrpcServiceMesh::UnknownError, "store is down"`
raises an `UNKNOWN` error. `MeshError.new` takes a code first and raises
`ArgumentError` without one. `MeshError.new` and
`MeshError.from_proto` return the subclass for the code they are given, so an
error decoded off the wire is rescued by its class. A code with no name stays
a plain `MeshError`, and `rescue GrpcServiceMesh::MeshError` catches every
code.

A name that is not a `Google::Rpc::Code` raises `ArgumentError`, and a detail
that is not a protobuf message raises `TypeError`.

**A route handler that raises `MeshError`** produces a normal reply whose
payload is the encoded `Status` and whose metadata carries `Grpc-Status` set
to the code as a decimal string, beside `Content-Type`. **A route handler that
raises anything else** (any `StandardError`) is reported the same way with
code `UNKNOWN` (2) and the exception's message. A request payload that does
not decode as the input class, and a response that is not an instance of the
output class, are reported through the same path. **A topic handler that
raises** passes its exception to the transport's runtime unchanged; the
transport documents what it does with it.

**A client method** reads `Grpc-Status` from the reply metadata before the
payload. When it is present the payload decodes as `Status` and the method
raises the `MeshError`. When it is absent the payload decodes as the output
class. Either payload failing to decode raises a `MeshError` with code
`INTERNAL` (13). Service Mesh API errors such as `ServiceMesh::KindMismatch`
and the transport's own errors pass through unchanged.

The errors this library raises for misuse of its own contract descend from
`GrpcServiceMesh::Error`.

| error | raised when |
|---|---|
| `UnknownTransport` | a transport name the router does not hold is asked for a client, or named by a target's metadata |

## Wire format

Every message this library sends carries metadata
`Content-Type: application/x-protobuf`, merged over the application's metadata. A
reply that reports a `MeshError` also carries `Grpc-Status`. Payloads are the
messages' binary encodings.

## Public API

| constant | role |
|---|---|
| `GrpcServiceMesh.transport_router` | the process `TransportRouter` |
| `GrpcServiceMesh.add_transport(name, client)` | shortcut for `transport_router.add` |
| `GrpcServiceMesh.registry` | the process `Registry` |
| `GrpcServiceMesh.register(service)` | shortcut for `registry.register` |
| `GrpcServiceMesh::TransportRouter` | `#add(name, client)`, `#client(name)`, `#names`, `#close`; holds one client per transport name |
| `GrpcServiceMesh::Registry` | `#register(service)`, `#endpoints(deployment_group)`, `#subscribers(deployment_group)` |
| `GrpcServiceMesh::RPCRuntime.new(transport:, deployment_group:, runtime:, config: {}, endpoints: nil, subscribers: nil)` | `#start`, `#stop(drain)`, `#running?`, `#client`, `#t_runtime`, `#transport`, `#deployment_group` |
| `GrpcServiceMesh::RPCService` | base class; `.rpc(...)`, `.rpcs`, `#endpoints`, `#subscribers`; a handler method takes `(request)` |
| `GrpcServiceMesh::RPCClient` | base class; `.rpc(...)` defines a class method per rpc, `name(request)`, `.rpcs` |
| `GrpcServiceMesh::Metadata` | module adding `#mesh_metadata` and `#mesh_metadata=` to a message class |
| `GrpcServiceMesh::Rpc` | a `Data` with `name`, `target`, `input`, `output`, `kind`, `owner`, `#route?` |
| `GrpcServiceMesh::MeshError` | above |
| `GrpcServiceMesh::OPTION_PREFIX` | `"Mesh-Option-"`, the start of a metadata key that is a transport option |
| `GrpcServiceMesh::Wire` | `CONTENT_TYPE_KEY`, `CONTENT_TYPE`, `GRPC_STATUS_KEY` |

The module-level accessors build the router and the registry on first use.

## Generated code

The generator is `grpc-service-mesh-gen` from the specification repository:

```sh
go install github.com/Paymentbox-com/grpc-service-mesh-api/cmd/grpc-service-mesh-gen@v0.8.0
grpc-service-mesh-gen --definitions definitions --go_out=lib/go --ruby_out=lib/ruby
```

The generator reads `mesh/options.proto` from its own module version and
puts that directory on every `protoc` run.

It writes one `<dir>_grpcmesh.rb` per directory that holds a
service, beside the `*_pb.rb` files protoc writes, and one `service_maps.rb`
at the output root. After the service classes, it includes
`GrpcServiceMesh::Metadata` into every message class an rpc in the file takes
or returns. For `examples/shop/order.proto` and `deployment.proto` from the
specification, `shop/shop_grpcmesh.rb` is:

```ruby
# frozen_string_literal: true

# Generated by grpc-service-mesh-gen. DO NOT EDIT.
# source: shop/order.proto
# transport: nats
# deployment group: shop

require "grpc_service_mesh"
require "google/protobuf/empty_pb"
require_relative "order_pb"

module Shop
  module OrderTargets
    PLACE = ServiceMesh::Target.new(
      segments: ["shop", "OrderService", "Place"],
      kind: :route,
      metadata: {"deployment_group" => "shop", "transport" => "nats"}
    )
    PLACED = ServiceMesh::Target.new(
      segments: ["shop", "OrderService", "Placed"],
      kind: :topic,
      metadata: {"deployment_group" => "shop", "transport" => "nats", "consumer_group" => "audit"}
    )
  end

  class OrderService < GrpcServiceMesh::RPCService
    rpc :place, target: OrderTargets::PLACE, input: Shop::Order, output: Shop::Order, kind: :route
    rpc :placed, target: OrderTargets::PLACED, input: Shop::Order, kind: :topic
  end

  class OrderClient < GrpcServiceMesh::RPCClient
    rpc :place, target: OrderTargets::PLACE, input: Shop::Order, output: Shop::Order, kind: :route
    rpc :placed, target: OrderTargets::PLACED, input: Shop::Order, kind: :topic
  end
end

::Google::Protobuf::Empty.include(GrpcServiceMesh::Metadata)
::Shop::Order.include(GrpcServiceMesh::Metadata)
```

and `service_maps.rb` is:

```ruby
# frozen_string_literal: true

# Generated by grpc-service-mesh-gen. DO NOT EDIT.
# One ServiceMap per transport, holding every Target served over it.

require "service_mesh"
require_relative "shop/shop_grpcmesh"

module ServiceMaps
  NATS = ServiceMesh::ServiceMap.new(targets: [
    Shop::OrderTargets::PLACE,
    Shop::OrderTargets::PLACED
  ])
end
```

Both files live in this repository under `spec/support/testproto/` as the
reference the specs run against.

### DSL reference

`RPCService` and `RPCClient` share one class-level declaration:

```ruby
rpc name, target:, input:, kind:, output: nil
```

| argument | value |
|---|---|
| `name` | a Symbol, the snake_case of the rpc name; the handler method on a service subclass and the class method on the client |
| `target:` | the `ServiceMesh::Target` constant for the rpc |
| `input:` | the input message class protoc generated |
| `output:` | the output message class protoc generated; required for `:route`, not used for `:topic` |
| `kind:` | `:route` or `:topic`, matching `target.kind` |

A `kind:` that disagrees with the target raises `ServiceMesh::KindMismatch`
when the file loads. `.rpcs`
returns every declared rpc by name, including those of superclasses, as
`GrpcServiceMesh::Rpc` values.

On an `RPCService` subclass the declaration records the rpc; `#endpoints`
returns a `ServiceMesh::Endpoint` for each route whose method the instance's
class defines at or below the declaring class, and `#subscribers` a
`ServiceMesh::Subscriber` for each such topic. The handler in each decodes
the payload with `input.decode`, sets the decoded message's `mesh_metadata` to
the inbound metadata, calls the method with it, and encodes the response with
`to_proto`, sending the response's `mesh_metadata`, without keys that start
with `Mesh-Option-`, as the reply's metadata.

On an `RPCClient` subclass the declaration defines the class method
`name(request)`. It splits the request's `mesh_metadata` into the message
metadata and the options. A route method calls the transport client's
`request(message, options)` and decodes the reply, setting the response's
`mesh_metadata` to the reply's metadata without `Mesh-Option-` keys; a topic
method calls `publish(message, options)` and returns `nil`. The transport is
`target.metadata["transport"]`, resolved through
`GrpcServiceMesh.transport_router.client` on every call.

Targets are plain `ServiceMesh::Target` values with segments from the proto
package, service name, and method name, and metadata `deployment_group`,
`transport`, and `consumer_group` when the method option is set. Nothing reads
proto options at runtime.

## Specification protos

`lib/mesh/options_pb.rb` is protoc's Ruby output of the specification's
`mesh/options.proto`. It adds the file to the generated descriptor pool,
which then resolves the extensions `mesh.kind`, `mesh.consumer_group`,
`mesh.deployment_group`, and `mesh.transport`, and defines `Mesh::Kind`. It
is compiled from the
[grpc-service-mesh-api](https://github.com/Paymentbox-com/grpc-service-mesh-api)
tag named by `spec_tag` in the `justfile`.

The compiled forms of `google/rpc/*.proto` are the published ones in
`googleapis-common-protos-types`.

Every `*_pb.rb` protoc writes from a definitions file that imports
`mesh/options.proto` calls `require 'mesh/options_pb'`, which resolves from
this gem's `lib`. Plain `protoc` takes the specification's files from the
directory `grpc-service-mesh-gen proto-path` prints:

```sh
protoc \
  -I definitions \
  -I "$(grpc-service-mesh-gen proto-path)" \
  --ruby_out=lib/ruby \
  $(find definitions -name '*.proto')
```

Only files under `definitions/` are listed. The specification's files are
only on the include path. A project that runs this command itself runs the
generator with `--mesh-only`, which writes the mesh code and skips the
message runs.

## Development

```
mise install
just install
just check      # lint, test, build
```

| recipe | what it does |
|---|---|
| `just proto` | run `just proto-spec` and `just proto-test` |
| `just proto-spec` | compile `mesh/options.proto` from grpc-service-mesh-api at `spec_tag` into `lib/mesh/options_pb.rb` |
| `just proto-test` | regenerate `spec/support/testproto/shop/order_pb.rb` |

### Updating the compiled specification protos

`lib/mesh/options_pb.rb` is the compiled form of `mesh/options.proto` in the
specification repository,
[grpc-service-mesh-api](https://github.com/Paymentbox-com/grpc-service-mesh-api),
at the tag `spec_tag` names in the `justfile`. It is never edited here.
`just proto-spec` makes a shallow clone of that tag in a temporary
directory, compiles `mesh/options.proto` from it with `protoc`, and removes
the clone. CI runs `just proto` and fails when the result differs from what
is committed, so the compiled form always matches the stated tag.

`mesh/options.proto` changes only by adding, so a new specification tag only
adds options or enum values. To adopt one:

1. Set `spec_tag` in the `justfile` to the new tag.
2. Run `just proto`.
3. Review the diff under `lib/mesh/`.
4. Run `just check`.
5. Bump the version in `lib/grpc_service_mesh/version.rb`, commit, and run
   `just tag`.

The extension numbers in `mesh/options.proto` are part of every definitions
project's compiled descriptors, and the specification never changes or
reuses one.

## Tests

```
just test
```

The specs run against an in-process transport in `spec/support/memory_transport.rb`
whose client records what it was given, whose runtime subscribes on the client's
bus and closes the client on stop, and which raises
`ServiceMesh::KindMismatch` on kind misuse. `spec/support/testproto/` holds the
`shop.Order` message, its protoc output, and the reference generated files
above; `just proto-test` regenerates the message class with `protoc`.
`spec/mesh_options_spec.rb` loads `mesh/options_pb` and checks the four
extensions in the descriptor pool.
`spec/spec_helper.rb` gives every example an empty process router and
registry.
