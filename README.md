# grpc-service-mesh-ruby

The Ruby library for the
[gRPC Service Mesh API](https://github.com/Paymentbox-com/grpc-service-mesh-api),
packaged as the gem `grpc_service_mesh`, module `GrpcServiceMesh`. The
specification is the authority for everything this gem does. The library
provides the non-generated types the specification names, `TransportRouter`,
`Registry`, `RPCRuntime`, and `MeshError`, together with the two base classes
the generator's Ruby output builds on, `RPCService` and `RPCClient`.

The Service Mesh API types and errors come from
[service-mesh-ruby](https://github.com/Paymentbox-com/service-mesh-ruby), gem
`service_mesh`. Transports are separate gems that the application configures at
boot; the NATS one is
[service-mesh-nats-ruby](https://github.com/Paymentbox-com/service-mesh-nats-ruby).
The Go counterparts are
[service-mesh-go](https://github.com/Paymentbox-com/service-mesh-go),
[service-mesh-nats-go](https://github.com/Paymentbox-com/service-mesh-nats-go),
and [grpc-service-mesh-go](https://github.com/Paymentbox-com/grpc-service-mesh-go).
The foundation specification is
[service-mesh-api](https://github.com/Paymentbox-com/service-mesh-api).

## Install

The gem and its `service_mesh` dependency come from their repositories at a
tag; Bundler needs both git sources in the Gemfile.

```ruby
# Gemfile
gem "grpc_service_mesh", git: "https://github.com/Paymentbox-com/grpc-service-mesh-ruby", tag: "v0.1.0"
gem "service_mesh", git: "https://github.com/Paymentbox-com/service-mesh-ruby", tag: "v0.2.0"
gem "service_mesh_nats", git: "https://github.com/Paymentbox-com/service-mesh-nats-ruby", tag: "v0.2.0" # or another transport
```

Requires Ruby 3.3 or newer. Depends on `service_mesh`, `google-protobuf`, and
`googleapis-common-protos-types`, which provides `Google::Rpc::Status`,
`Google::Rpc::Code`, and the detail types in `google/rpc/error_details.proto`.
No transport is a dependency.

## Usage

The examples use the generated code shown under Generated code: the
`Pbx::ApiKeyService`, `Pbx::ApiKeyClient`, and `Pbx::ApiKeyTargets` produced
from the specification's `examples/pbx/api_key.proto`, and `ServiceMaps::NATS`
produced from every target on the `nats` transport.

### Configuring the TransportRouter at boot

The process has one `TransportRouter`, `GrpcServiceMesh.transport_router`. Each
transport the generated code names is added once, with the transport's
configuration Hash, the generated `ServiceMap` for it, and two lambdas that
build the transport's `Runtime` and `Client`. Nothing generated takes a router
argument; generated clients and `RPCRuntime` find the process router
themselves.

```ruby
require "grpc_service_mesh"
require "service_mesh_nats"
require "service_maps"

GrpcServiceMesh.add_transport("nats",
  config: {"url" => ENV.fetch("NATS_URL", "nats://127.0.0.1:4222")},
  service_map: ServiceMaps::NATS,
  runtime: ->(config, map, endpoints:, subscribers:) { ServiceMeshNats::Runtime.new(config, map, endpoints: endpoints, subscribers: subscribers) },
  client: ->(config, map) { ServiceMeshNats::Client.new(config, map) })
```

The `runtime` lambda receives the transport's configuration with
`deployment_group` filled in, the transport's `ServiceMap`, and the
`Endpoints` and `Subscribers` the `RPCRuntime` collected. The `client` lambda
receives the configuration as given and the same map. `add_transport` under
a name already present replaces the entry.

`transport_router.client(name)` returns the transport's `Client`. Once an
`RPCRuntime` exists for the transport, that is the runtime's own client, so a
process that serves and calls over one transport uses one connection.
Otherwise it is a standalone client built once from the `client` lambda and
kept until `transport_router.close`, which closes every standalone client
the router built and forgets it; a process that only calls runs it before
exit so the transport flushes what it has buffered. The runtime's `stop`
closes the client the runtime owns. A name the router does not hold raises
`GrpcServiceMesh::UnknownTransport`.

### Registering a service

The generated `Pbx::ApiKeyService` declares the rpcs of the proto service and
serves nothing itself. The application subclasses it and defines a method for
each rpc it serves. The method takes the decoded request and the inbound
message metadata Hash. A route method returns the response message; a topic
method's return value is ignored.

```ruby
class ApiKeys < Pbx::ApiKeyService
  def initialize(store)
    @store = store
  end

  def search(request, metadata)
    key = @store.find(request.first_name) or
      raise GrpcServiceMesh::NotFoundError.new("no key for #{request.first_name}",
        Google::Rpc::ErrorInfo.new(reason: "KEY_MISSING", domain: "pbx", metadata: {"request_id" => metadata["Request-Id"].to_s}))
    Pbx::ApiKey.new(first_name: key.first_name, last_name: key.last_name)
  end

  def created(request, metadata)
    @store.record(request)
  end
end

GrpcServiceMesh.register(ApiKeys.new(store))
```

`GrpcServiceMesh.register` takes an instance and adds its `endpoints` and
`subscribers` to the process `Registry`, `GrpcServiceMesh.registry`. A subclass
serves exactly the rpc methods defined in it or below it; an rpc whose method
is missing is not bound. Every registered binding is kept, so two
registrations of one target hand the transport two bindings for it.

### Starting an RPCRuntime

An `RPCRuntime` serves one transport and one deployment group. Its
constructor takes the registry's endpoints and subscribers whose target
metadata `deployment_group` matches, fetches the transport entry from the
router, and calls the entry's `runtime` lambda with the entry's configuration
merged with `"deployment_group"`, the entry's `ServiceMap`, and those
bindings. Services registered after construction are not served by it. The
constructor also records the runtime on the router, so the router hands out
its client from then on. A second `RPCRuntime` for a transport becomes the
one the router's `client` uses.

```ruby
runtime = GrpcServiceMesh::RPCRuntime.new(transport: "nats", deployment_group: "pbx")
runtime.start
at_exit { runtime.stop(10) }
```

`start`, `stop(drain)`, `running?`, and `client` delegate to the transport's
`Runtime`, which `underlying` exposes. The transport documents what its
runtime does, including what `stop` returns and how it treats a subscriber
handler that raises.

### Calling a service

Generated client methods are class methods taking the request message and two
keywords. `metadata:` is added to the outbound message's metadata and
`options:` is the per-call Hash the transport's `request` or `publish` takes.
Both default to empty. Every call resolves the transport's `Client` through
the router, so the same code runs in a process that serves and in one that
only calls.

```ruby
begin
  key = Pbx::ApiKeyClient.search(Pbx::ApiKey.new(first_name: "ada"),
    metadata: {"Request-Id" => SecureRandom.uuid},
    options: {"request_timeout" => "2"})
rescue GrpcServiceMesh::NotFoundError => e
  e.message                # "no key for ada"
  info = e.details.find { |d| d.is(Google::Rpc::ErrorInfo) }&.unpack(Google::Rpc::ErrorInfo)
rescue GrpcServiceMesh::MeshError => e
  e.code                   # any other Google::Rpc::Code name
rescue NATS::Timeout, NATS::IO::NoRespondersError
  # transport errors pass through unchanged
end

Pbx::ApiKeyClient.created(Pbx::ApiKey.new(first_name: "ada"), metadata: {"Event-Id" => "e1"})
```

A route method returns the decoded response. A topic method returns `nil`. A
request that is not an instance of the rpc's input class raises `TypeError`
before anything is sent.

## Errors

`GrpcServiceMesh::MeshError` descends from `StandardError` and wraps a
`Google::Rpc::Status`.

| member | value |
|---|---|
| `MeshError.new(code, message, *details)` | `code` is a `Google::Rpc::Code` name such as `:NOT_FOUND` or its number such as `5`; `details` are protobuf messages, packed into `Google::Protobuf::Any`, or `Any` values already packed |
| `MeshError.from_proto(status)` | wraps a `Google::Rpc::Status` |
| `#code` | the `Google::Rpc::Code` name, or the number when it has no name |
| `#message` | the text, also what `to_s` returns |
| `#details` | an Array of `Google::Protobuf::Any`; unpack with `any.unpack(klass)`, test with `any.is(klass)` |
| `#proto` | the `Google::Rpc::Status` |

`MeshError` has one subclass per `Google::Rpc::Code` other than `OK`:
`NotFoundError`, `InvalidArgumentError`, `PermissionDeniedError`,
`UnauthenticatedError`, `FailedPreconditionError`, `InternalError`,
`UnavailableError`, and the rest, each named after its code. A subclass is
built from a message and details, `GrpcServiceMesh::NotFoundError.new("no
such key", info)`, and fixes its own code. `MeshError.new` and
`MeshError.from_proto` return the subclass for the code they are given, so an
error decoded off the wire is rescued by its class. A code with no name stays
a plain `MeshError`, and `rescue GrpcServiceMesh::MeshError` catches every
code.

A name that is not a `Google::Rpc::Code` raises `ArgumentError`.

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
| `UnknownTransport` | a transport name the router does not hold is fetched, asked for a client, or named by a target's metadata |

## Wire format

Every message this library sends carries metadata
`Content-Type: application/x-protobuf`, merged over the caller's metadata. A
reply that reports a `MeshError` also carries `Grpc-Status`. Payloads are the
messages' binary encodings.

## Public API

| constant | role |
|---|---|
| `GrpcServiceMesh.transport_router` | the process `TransportRouter` |
| `GrpcServiceMesh.add_transport(name, config:, service_map:, runtime:, client:)` | shortcut for `transport_router.add` |
| `GrpcServiceMesh.registry` | the process `Registry` |
| `GrpcServiceMesh.register(service)` | shortcut for `registry.register` |
| `GrpcServiceMesh.reset!` | test support: replaces the process router and registry with empty ones |
| `GrpcServiceMesh::TransportRouter` | `#add(name, config:, service_map:, runtime:, client:)`, `#fetch(name)`, `#names`, `#client(name)`, `#close`, `#attach_runtime(name, rpc_runtime)`, `#runtime(name)`; `TransportRouter::Transport` is the entry, a `Data` with `config`, `service_map`, `runtime`, `client` |
| `GrpcServiceMesh::Registry` | `#register(service)`, `#endpoints(deployment_group)`, `#subscribers(deployment_group)` |
| `GrpcServiceMesh::RPCRuntime.new(transport:, deployment_group:)` | `#start`, `#stop(drain)`, `#running?`, `#client`, `#underlying`, `#transport`, `#deployment_group` |
| `GrpcServiceMesh::RPCService` | base class; `.rpc(...)`, `.rpcs`, `#endpoints`, `#subscribers` |
| `GrpcServiceMesh::RPCClient` | base class; `.rpc(...)` defines a class method per rpc, `.rpcs` |
| `GrpcServiceMesh::Rpc` | a `Data` with `name`, `target`, `input`, `output`, `kind`, `owner`, `#route?` |
| `GrpcServiceMesh::MeshError` | above |
| `GrpcServiceMesh::Wire` | `CONTENT_TYPE_KEY`, `CONTENT_TYPE`, `GRPC_STATUS_KEY` |

The router and the registry are guarded by a `Mutex`; the module-level
accessors build them on first use.

## Generated code

The generator is `grpc-service-mesh-gen` from the specification repository:

```sh
go install github.com/Paymentbox-com/grpc-service-mesh-api/cmd/grpc-service-mesh-gen@v0.1.0
grpc-service-mesh-gen --definitions definitions --out lib --lang go,ruby
```

It writes one `<dir>_grpcmesh.rb` per directory that holds a
service, beside the `*_pb.rb` files protoc writes, and one `service_maps.rb`
at the output root. For `examples/pbx/api_key.proto` and `deployment.proto`
from the specification, `pbx/pbx_grpcmesh.rb` is:

```ruby
# frozen_string_literal: true

# Generated by grpc-service-mesh-gen. DO NOT EDIT.
# source: pbx/api_key.proto
# transport: nats
# deployment group: pbx

require "grpc_service_mesh"
require_relative "api_key_pb"

module Pbx
  module ApiKeyTargets
    SEARCH = ServiceMesh::Target.new(
      segments: ["pbx", "ApiKeyService", "Search"],
      kind: :route,
      metadata: {"deployment_group" => "pbx", "transport" => "nats"}
    )
    CREATED = ServiceMesh::Target.new(
      segments: ["pbx", "ApiKeyService", "Created"],
      kind: :topic,
      metadata: {"deployment_group" => "pbx", "transport" => "nats", "consumer_group" => "audit"}
    )
  end

  class ApiKeyService < GrpcServiceMesh::RPCService
    rpc :search, target: ApiKeyTargets::SEARCH, input: Pbx::ApiKey, output: Pbx::ApiKey, kind: :route
    rpc :created, target: ApiKeyTargets::CREATED, input: Pbx::ApiKey, kind: :topic
  end

  class ApiKeyClient < GrpcServiceMesh::RPCClient
    rpc :search, target: ApiKeyTargets::SEARCH, input: Pbx::ApiKey, output: Pbx::ApiKey, kind: :route
    rpc :created, target: ApiKeyTargets::CREATED, input: Pbx::ApiKey, kind: :topic
  end
end
```

and `service_maps.rb` is:

```ruby
# frozen_string_literal: true

# Generated by grpc-service-mesh-gen. DO NOT EDIT.
# One ServiceMap per transport, holding every Target served over it.

require "service_mesh"
require_relative "pbx/pbx_grpcmesh"

module ServiceMaps
  NATS = ServiceMesh::ServiceMap.new(targets: [
    Pbx::ApiKeyTargets::SEARCH,
    Pbx::ApiKeyTargets::CREATED
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

A `kind:` that disagrees with the target, a kind outside those two, or a
route without `output:` raises `ArgumentError` when the file loads. `.rpcs`
returns every declared rpc by name, including those of superclasses, as
`GrpcServiceMesh::Rpc` values.

On an `RPCService` subclass the declaration records the rpc; `#endpoints`
returns a `ServiceMesh::Endpoint` for each route whose method the instance's
class defines at or below the declaring class, and `#subscribers` a
`ServiceMesh::Subscriber` for each such topic. The handler in each decodes
the payload with `input.decode`, calls the method with the message and its
metadata Hash, and encodes the response with `to_proto`.

On an `RPCClient` subclass the declaration defines the class method
`name(request, metadata: {}, options: {})`. A route method calls the
transport client's `request(message, options)` and decodes the reply; a topic
method calls `publish(message, options)` and returns `nil`. The transport is
`target.metadata["transport"]`, resolved through
`GrpcServiceMesh.transport_router.client` on every call.

Targets are plain `ServiceMesh::Target` values with segments from the proto
package, service name, and method name, and metadata `deployment_group`,
`transport`, and `consumer_group` when the method option is set. Nothing reads
proto options at runtime.

## Development

```
mise install
just install
just check      # lint, test, build
```

## Tests

```
just test
```

The specs run against an in-process transport in `spec/support/memory_transport.rb`
whose runtime and client record what they were given and raise
`ServiceMesh::KindMismatch` on kind misuse. `spec/support/testproto/` holds the
`pbx.ApiKey` message, its protoc output, and the reference generated files
above; `just proto` regenerates the message class with `protoc`.
`GrpcServiceMesh.reset!` runs before each example so every example starts
from an empty router and registry.
