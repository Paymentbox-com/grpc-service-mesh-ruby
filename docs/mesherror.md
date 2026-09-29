# MeshError

`GrpcServiceMesh::MeshError` wraps a `Google::Rpc::Status` and descends from
`StandardError`.

```ruby
me = GrpcServiceMesh::NotFoundError.new("no such item", Google::Rpc::ErrorInfo.new(reason: "GONE"))
me.code          # :NOT_FOUND
me.message       # "no such item", also what to_s returns
me.details       # an Array of Google::Protobuf::Any
me.proto         # the wrapped Google::Rpc::Status
me.mesh_metadata # the reply metadata, from GrpcServiceMesh::Metadata

back = GrpcServiceMesh::MeshError.from_proto(status) # status is a Google::Rpc::Status; back is a NotFoundError when its code is NOT_FOUND
```

There is one subclass per `Google::Rpc::Code` other than `OK`, named after its
code: `NotFoundError`, `InvalidArgumentError`, `PermissionDeniedError`, and so
on. Each is `MeshError` with its code fixed, built from a message, details, and
`mesh_metadata:`. `raise GrpcServiceMesh::NotFoundError, "no such item"` builds
the same error with no details.

`MeshError.new(code, message, *details, mesh_metadata: {})` takes any code, as
a `Google::Rpc::Code` name such as `:NOT_FOUND` or its number such as `5`.
`MeshError.new` and `MeshError.from_proto` return the subclass for the code
they are given, so an error decoded from a reply can be rescued by its class.
A code with no name stays a plain `MeshError`, and
`rescue GrpcServiceMesh::MeshError` catches every code. `#code` is the code's
name, or its number when it has no name.

`MeshError.new` packs each detail message into `Google::Protobuf::Any`, and an
`Any` that is already packed is kept as it is.

## Library Errors

These are the errors the library itself raises, apart from a `MeshError`.

| Error | Raised when |
|---|---|
| `GrpcServiceMesh::UnknownTransport` | `transport_router.client`, `RPCRuntime.new`, or a client method looks up a transport name that was not added to the router. The message names the transport. |
| `GrpcServiceMesh::CloseFailed` | `transport_router.close` could not close one or more clients. `failures` maps each transport name to the exception its client raised, and the message lists each one. |
| `ArgumentError` | `RPCRuntime.new` is given a `runtime:` that does not respond to `call`. |
| `ArgumentError` | A `Target` given through `endpoints:` or `subscribers:` carries a different `deployment_group` or `transport` from the runtime. The message names the Target's segments and the key that differs. |
| `ArgumentError` | `MeshError.new` is given no code, or a code that is not a `Google::Rpc::Code` name or number. |
| `TypeError` | A client method is given a request that is not an instance of the rpc's input class. |
| `TypeError` | `mesh_metadata=` is given a value that is not a Hash, or a `MeshError` detail is not a protobuf message. |
| `ServiceMesh::KindMismatch` | An `rpc` declaration's `kind:` does not match its target's kind. It is raised when the file loads. |
| `MeshError` with `INTERNAL` | A payload fails to decode. A client method raises it when the reply does not decode, and when the serving handler could not decode the request. |

`UnknownTransport` and `CloseFailed` descend from `GrpcServiceMesh::Error`. Errors from the
Service Mesh API, from the transport, and from `runtime:` pass through
unchanged.
