# Handlers

## Message Metadata

Message metadata travels on the message objects themselves. The generated
code includes the `GrpcServiceMesh::Metadata` module into every message class
that an rpc takes or returns. The module adds two methods.

| Method | Behavior |
|---|---|
| `#mesh_metadata` | Returns the object's metadata Hash. The first read on an object with no metadata stores a new empty Hash on it, so keys can be written into it directly. A frozen object with no metadata returns a frozen empty Hash. |
| `#mesh_metadata=(hash)` | Sets the metadata. `nil` clears it, and a value that is not a Hash raises `TypeError`. |

The library sets `mesh_metadata` on the objects it builds. These are the
decoded request a handler receives, and the decoded response or `MeshError` a
caller receives.

The library only reads `mesh_metadata` on the objects the application gives
it, which are the request a caller sends and the response a handler returns.
It never writes to them, so a handler may return a shared or frozen object.

`MeshError` includes the module as well. A message class that declares its own
field named `mesh_metadata` can't carry metadata, so the generator rejects it.

## Endpoint Handlers

A route handler receives the decoded request and returns the response, or
raises. A `MeshError` is the application failure the caller receives. Inbound
message metadata is read from the request's `mesh_metadata`.

```ruby
def place(request)
  if request.mesh_metadata["Tenant"].to_s.empty?
    raise GrpcServiceMesh::InvalidArgumentError.new("Tenant is required",
      Google::Rpc::ErrorInfo.new(reason: "MISSING_TENANT", domain: "shop"))
  end
  Shop::Order.new(id: @store.place(request.item), item: request.item)
end
```

## Returning an Error

A handler reports an application failure by raising a [`MeshError`](mesherror.md).
The per-code subclasses, such as `NotFoundError` and `InvalidArgumentError`,
take the message and any detail messages. `MeshError.new(code, message, *details)`
takes any `Google::Rpc::Code`.

```ruby
def place(request)
  unless @store.in_stock?(request.item)
    raise GrpcServiceMesh::NotFoundError.new("no such item",
      Google::Rpc::ErrorInfo.new(reason: "ITEM_MISSING", domain: "shop"))
  end
  Shop::Order.new(id: @store.place(request.item), item: request.item)
end
```

A `MeshError` becomes a reply whose payload is the encoded
`Google::Rpc::Status` and whose metadata carries `Grpc-Status`, the code as a
decimal integer string, beside `Content-Type`.

Any other `StandardError`, including a response that is not an instance of the
rpc's output class, is reported the same way as `UNKNOWN` (2), with the
failure's message.

A request that does not decode is reported as `INTERNAL` (13), the code every
decoding failure carries. The message names the message type, such as
`request does not decode as shop.Order: ...`.

In the Service Mesh API, an endpoint handler returns a reply message or raises,
and a transport reports a raised error to the caller in its own way. The
handler that `RPCService` builds always returns a reply message for any
`StandardError`, even for a failure. A caller therefore receives every handler
failure as a `MeshError`, and never as the transport's own handler error.

## Reply Metadata

A route handler sets metadata on its reply through the `mesh_metadata` of the
response it returns. When it raises a `MeshError`, the reply's metadata is the
error's `mesh_metadata`, which the error takes on construction as
`mesh_metadata:` or through `mesh_metadata=`. The `UNKNOWN` reply for any other
failure carries only the library's keys. The library writes `Content-Type` and
`Grpc-Status` over the application's values, so its own values win, and a
successful reply carries no `Grpc-Status`. Keys that start with `Mesh-Option-`
are removed from the reply's metadata. A topic handler has no reply, so
metadata it sets goes nowhere.

```ruby
def place(request)
  unless @store.in_stock?(request.item)
    raise GrpcServiceMesh::NotFoundError.new("no such item", mesh_metadata: {"Retry-After" => "30"})
  end
  order = Shop::Order.new(id: @store.place(request.item), item: request.item)
  order.mesh_metadata["Request-Id"] = "7"
  order
end
```

## Subscriber Handlers

A topic handler receives the decoded message, and its return value is ignored.

A topic message has no reply, so the handler that `RPCService` builds lets an
exception from the handler propagate to the transport unchanged. The transport
documents what it does with it.

A message that does not decode is handled the same way. The handler is not
called, and the transport receives a `Google::Protobuf::ParseError` that names
the message type, such as `request does not decode as shop.Order: ...`.
