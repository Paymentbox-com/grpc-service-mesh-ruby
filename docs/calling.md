# Calling

A [generated client](generated-code.md) is a class with one class method per
`rpc` method. Each method takes the request, whose `mesh_metadata` is the
outbound metadata. A route method returns the decoded response, whose
`mesh_metadata` is the reply's metadata, or raises. A topic method publishes
and returns `nil`, or raises.

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

order.mesh_metadata = request.mesh_metadata
Shop::OrderClient.placed(order)
```

A request that is not an instance of the rpc's input class raises `TypeError`
before anything is sent.

## Metadata and Transport Options

The keys of the request's `mesh_metadata` that start with `Mesh-Option-`
(`GrpcServiceMesh::OPTION_PREFIX`) are transport options. A client method
removes them from the message metadata and passes each one to the transport's
`request` or `publish` options with the prefix removed, so
`"Mesh-Option-request_timeout" => "2"` reaches the transport as option
`"request_timeout" => "2"`. The match is exact and case-sensitive. Every other
key is message metadata. The request's `mesh_metadata` is not modified. A
request with no metadata sends a message whose only metadata is
`Content-Type`, with no options.

Every call looks up the transport's `Client` through the router, so the same
calling code works in a process that serves and in one that only calls.

## Reply Metadata

The response a route method returns has its `mesh_metadata` set to the reply's
metadata, on a successful reply. A `MeshError` raised from a reply has its
`mesh_metadata` set the same way. An error raised before a reply arrives, such
as a transport error, carries none. Reply metadata never carries keys that
start with `Mesh-Option-`. The serving side drops them from the metadata a
handler sets, and the calling side drops them from the reply it receives.

## Reply Decoding

A route method reads `Grpc-Status` on the reply before the payload. When it is
set, the payload is decoded as `Google::Rpc::Status` and raised as a
`MeshError`, whose code is the one inside the `Status`. When it is not set, the
payload is decoded as the response class.

A payload that does not decode raises an `INTERNAL` (13) `MeshError` whose
message names the expected type, such as
`reply does not decode as shop.Order: ...`.

Errors from the router, the Service Mesh API, and the transport pass through
unchanged. The router's error is listed under
[Library Errors](mesherror.md#library-errors).

## Wire Format

Every message the library sends carries the metadata
`Content-Type: application/x-protobuf`. A `Content-Type` in the request's
`mesh_metadata` is overwritten.

A reply that reports a `MeshError` also carries `Grpc-Status`, the code as a
decimal integer string, and its payload is the encoded `Google::Rpc::Status`.
Every other payload is the message's binary protobuf encoding.
