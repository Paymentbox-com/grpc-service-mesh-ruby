# grpc-service-mesh-ruby

`grpc_service_mesh` is the Ruby implementation of the
[gRPC Service Mesh API](https://github.com/Paymentbox-com/grpc-service-mesh-api).
It carries protobuf messages over any transport that implements the
[Service Mesh API Specification](https://github.com/Paymentbox-com/service-mesh-api)
through the Ruby contract in the `service_mesh` gem, from
[service-mesh-ruby](https://github.com/Paymentbox-com/service-mesh-ruby).

The `GrpcServiceMesh` module holds the specification's non-generated types:
* `TransportRouter`
* `Registry`
* `RPCRuntime`
* `MeshError`

It also holds the two base classes that generated code builds on:
* `RPCService`
* `RPCClient`

Generated code comes from `grpc-service-mesh-gen` in the specification
repository and lives in a definitions project.

## Install

The gem and its `service_mesh` dependency are installed from their
repositories at a tag, so the Gemfile names both git sources.

```ruby
# Gemfile
gem "grpc_service_mesh", git: "https://github.com/Paymentbox-com/grpc-service-mesh-ruby", tag: "v0.15.0"
gem "service_mesh", git: "https://github.com/Paymentbox-com/service-mesh-ruby", tag: "v0.4.2"
```

Requires Ruby 3.3 or newer. The gem depends on `service_mesh`,
`google-protobuf`, and `googleapis-common-protos-types`. The last of these
provides `Google::Rpc::Status`, `Google::Rpc::Code`, and the detail types in
`google/rpc/error_details.proto`.

No transport is a dependency. The application adds the transport gem it uses.

## Usage

An application uses this library through the generated code that depends on it. The
[gRPC Service Mesh API](https://github.com/Paymentbox-com/grpc-service-mesh-api) describes how Ruby code is
generated from `.proto` files.

### Reference Examples

The examples in these docs use the `shop.OrderService` from the specification: a `ROUTE` method `Place` and a
`TOPIC` method `Placed`, served over the transport named `nats` in deployment group `shop`. The generated module is
`Shop`, with `Shop::OrderService`, `Shop::OrderClient`, and `Shop::OrderTargets`, and the generated per-transport maps
are in `ServiceMaps`. The library's own reference copy of that generated code is in `spec/support/testproto/`,
described under [Generated Code](docs/generated-code.md).

## Documentation

- [Setup](docs/setup.md): configuring the `TransportRouter`, registering services, and running an `RPCRuntime`
- [Handlers](docs/handlers.md): message metadata, writing route and topic handlers, returning errors, and setting reply metadata
- [Calling](docs/calling.md): calling generated clients, metadata and transport options, reply metadata, and the wire format
- [MeshError](docs/mesherror.md): constructing and reading `MeshError`, and the errors the library raises
- [Generated Code](docs/generated-code.md): what the generator emits for Ruby, with the reference files and the DSL
- [Public API](docs/public-api.md): every public constant and method in `GrpcServiceMesh`
- [Development](docs/development.md): the specification protos, the recipes, and the tests
