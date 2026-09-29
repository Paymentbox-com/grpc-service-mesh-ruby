# Calling

An application calls a service through its [generated
client](generated-code.md), a class with one class method per rpc method. Every
call looks up the transport's `Client` through the router, so the same calling
code works in a process that serves and in one that only calls, once the router
holds a client for the transport, as described under [Setup](setup.md).

Each method takes the request, whose `mesh_metadata` is the outbound metadata.
A `ROUTE` method returns the decoded response, whose `mesh_metadata` is the
reply's metadata, or raises. A `TOPIC` method publishes and returns `nil`, or
raises.

```ruby
request = Shop::Order.new(item: "book")
request.mesh_metadata = {
  "Tenant" => "acme",
  GrpcServiceMesh::OPTION_PREFIX + "request_timeout" => "2"
}

begin
  order = Shop::OrderClient.place(request)
  puts order.id, order.mesh_metadata["Request-Id"]
rescue GrpcServiceMesh::MeshError => e
  # e.code, e.message, e.details; a detail unpacks with unpack
  e.details.each do |d|
    info = d.unpack(Google::Rpc::ErrorInfo)
    puts info.reason if info
  end
rescue GrpcServiceMesh::UnknownTransport
  # the target's transport is not configured on the router
end
# Any other error is a Service Mesh API or transport error, unchanged, such as
# ServiceMesh::KindMismatch or the transport's timeout error.

event = Shop::Order.new(id: "o-1", item: "book")
event.mesh_metadata = {"Tenant" => "acme"}
Shop::OrderClient.placed(event)
```

A request that is not an instance of the rpc method's input class raises
`TypeError` before anything is sent.

## Metadata and Transport Options

The keys of the request's `mesh_metadata` that start with `Mesh-Option-`
(`GrpcServiceMesh::OPTION_PREFIX`) are transport options. A client method
removes them from the message metadata and passes each one to the transport's
`request` or `publish` options with the prefix removed. The match is exact and
case-sensitive.

For example, `"Mesh-Option-request_timeout" => "2"` reaches the transport as
the option `"request_timeout" => "2"`.

Every other key is sent as message metadata. The request's `mesh_metadata` is
not modified. A request with no metadata sends a message whose only metadata is
`Content-Type`, with no options.

## Reply Metadata

The response a `ROUTE` method returns has its `mesh_metadata` set to the
reply's metadata, on a successful reply. A `MeshError` raised from a reply has
its `mesh_metadata` set the same way. An error raised before a reply arrives,
such as a transport error, carries none. Reply metadata never carries keys that
start with `Mesh-Option-`. The serving side drops them from the metadata a
handler sets, and the calling side drops them from the reply it receives.

## Reply Decoding

A `ROUTE` method reads `Grpc-Status` on the reply before the payload. When it
is set, the payload is decoded as `Google::Rpc::Status` and raised as a
`MeshError`, whose code is the one inside the `Status`. When it is not set, the
payload is decoded as the response class.

A payload that does not decode raises an `INTERNAL` (13) `MeshError` whose
message names the expected type, such as
`reply does not decode as shop.Order: ...`.

A transport name the router does not hold raises
`GrpcServiceMesh::UnknownTransport`, a library error listed under
[Library Errors](mesherror.md#library-errors). Errors from the Service Mesh API
and from the transport pass through unchanged.

## Wire Format

Every message the library sends carries the metadata
`Content-Type: application/x-protobuf`. A `Content-Type` in the request's
`mesh_metadata` is overwritten.

A reply that reports a `MeshError` also carries `Grpc-Status`, the code as a
decimal integer string, and its payload is the encoded `Google::Rpc::Status`.
Every other payload is the message's binary protobuf encoding.
