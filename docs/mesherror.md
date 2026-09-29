# MeshError

`MeshError` is the application failure that travels from a handler to its
caller. A `ROUTE` handler raises one to report a failure, as described under
[Returning an Error](handlers.md#returning-an-error), and the caller receives
it from the generated client method, as described under
[Calling](calling.md). It wraps a `Google::Rpc::Status`, the standard protobuf
error message, so a caller in any language decodes the same code, message, and
details.

`GrpcServiceMesh::MeshError` descends from `StandardError`.

```ruby
me = GrpcServiceMesh::NotFoundError.new("no such item", Google::Rpc::ErrorInfo.new(reason: "GONE"))
me.code          # :NOT_FOUND
me.message       # "no such item", also what to_s returns
me.details       # an Array of Google::Protobuf::Any
me.proto         # the wrapped Google::Rpc::Status
me.mesh_metadata # the reply metadata, from GrpcServiceMesh::Metadata

back = GrpcServiceMesh::MeshError.from_proto(status) # status is a Google::Rpc::Status; back is a NotFoundError when its code is NOT_FOUND
```

`#code` is the code's name, or its number when the code has no name.

## Constructing a MeshError

There is one subclass per `Google::Rpc::Code` other than `OK`, named after its
code, such as `NotFoundError`, `InvalidArgumentError`, and
`PermissionDeniedError`. Each is `MeshError` with its code fixed, and takes the
message, any detail messages, and `mesh_metadata:`.
`raise GrpcServiceMesh::NotFoundError, "no such item"` builds the same error
with no details.

`MeshError.new(code, message, *details, mesh_metadata: {})` takes any code, as
a `Google::Rpc::Code` name such as `:NOT_FOUND` or its number such as `5`.

`MeshError.new` packs each detail message into `Google::Protobuf::Any`, and
keeps an `Any` that is already packed as it is. A detail that is not a
protobuf message raises `TypeError`.

## Reading a MeshError

`MeshError.new` and `MeshError.from_proto` return the subclass for the code
they are given, so an error decoded from a reply can be rescued by its class. A
code with no name stays a plain `MeshError`, and
`rescue GrpcServiceMesh::MeshError` catches every code.

```ruby
begin
  Shop::OrderClient.place(request)
rescue GrpcServiceMesh::NotFoundError
  # the order does not exist
end
```

## Library Errors

These are the errors the library itself produces. A `MeshError` that a handler
raises reaches the caller as described under
[Returning an Error](handlers.md#returning-an-error).

| Error | Raised when |
|---|---|
| `GrpcServiceMesh::UnknownTransport` | `transport_router.client`, `RPCRuntime.new`, or a client method looks up a transport name that was not added to the router. The message names the transport. |
| `GrpcServiceMesh::CloseFailed` | `transport_router.close` could not close one or more clients. `failures` maps each transport name to the exception its client raised, and the message lists each one. |
| `ArgumentError` | `RPCRuntime.new` is given a `runtime:` that does not respond to `call`. |
| `ArgumentError` | A `Target` given through `endpoints:` or `subscribers:` carries a different `deployment_group` or `transport` from the runtime. The message names the Target's segments and the key that differs. |
| `ArgumentError` | `MeshError.new` is given no code, or a code that is not a `Google::Rpc::Code` name or number. |
| `TypeError` | A client method is given a request that is not an instance of the rpc method's input class. |
| `TypeError` | `mesh_metadata=` is given a value that is not a Hash, or a `MeshError` detail is not a protobuf message. |
| `ServiceMesh::KindMismatch` | An `rpc` declaration's `kind:` does not match its target's kind. It is raised when the file loads. |
| `MeshError` with `INTERNAL` | A payload fails to decode. A client method raises it when the reply does not decode, and when the serving handler could not decode the request. |

`UnknownTransport` and `CloseFailed` descend from `GrpcServiceMesh::Error`.
Errors from the Service Mesh API, from the transport, and from `runtime:` pass
through unchanged.
