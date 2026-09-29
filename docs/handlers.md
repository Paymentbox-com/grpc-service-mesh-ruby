# Handlers

A handler is the application code that serves one rpc method. The generator
writes an `RPCService` subclass for each proto service, and that class declares
the service's rpc methods but serves none of them. The application implements
its handlers by subclassing the generated class and defining one method per rpc
method it serves. It then registers an instance of the subclass, as described
under [Registering a Service](setup.md#registering-a-service).

The library turns each method into a Service Mesh API `Endpoint`, for a `ROUTE`
rpc method, or `Subscriber`, for a `TOPIC` rpc method. Each one decodes the
inbound payload, calls the method, and for a `ROUTE` rpc method encodes the
reply. The sections below describe what a handler method receives, what it
returns, and how its failures reach the caller.

## Implementing an RPCService

The generated `Shop::OrderService` declares the `ROUTE` rpc method `place` and
the `TOPIC` rpc method `placed`, with the message class each one takes and
returns:

```ruby
class OrderService < GrpcServiceMesh::RPCService
  rpc :place, target: OrderTargets::PLACE, input: Shop::Order, output: Shop::Order, kind: :route
  rpc :placed, target: OrderTargets::PLACED, input: Shop::Order, kind: :topic
end
```

The application subclasses it and defines a method named after each rpc method.
Each method takes one argument, the decoded request. The subclass is an
ordinary Ruby class, so it can take its dependencies through `initialize` and
keep them on the instance.

In this example and the others on this page, `db_model` stands for the
application's own database model for orders, which this library knows nothing
about. Its `in_stock?(item)` says whether an item is available, and
`create(item)` saves a new order and returns the saved record, whose `id` and
`item` are its id and item. `logger` is a standard
Ruby `Logger`.

```ruby
class Orders < Shop::OrderService
  def initialize(db_model, logger)
    @db_model = db_model
    @logger = logger
  end

  # ROUTE: returns a Shop::Order
  def place(request)
    order = @db_model.create(request.item)
    Shop::Order.new(id: order.id, item: order.item)
  end

  # TOPIC: the return value is ignored
  def placed(event)
    @logger.info("order placed: #{event.id}")
  end
end

GrpcServiceMesh.register(Orders.new(db_model, logger))
```

An instance serves every rpc method that has a method defined on its class, or
on a superclass below the generated class. An rpc method the subclass does not
define is not served, so a process can implement only some of a service's rpc
methods.

## Endpoint Handlers

A `ROUTE` handler receives the decoded request and returns the response, which
must be an instance of the rpc method's output class. The inbound message
metadata is on the request, as its `mesh_metadata`, described under [Message
Metadata](#message-metadata).

```ruby
def place(request)
  if request.mesh_metadata["Tenant"].to_s.empty?
    raise GrpcServiceMesh::InvalidArgumentError.new("Tenant is required",
      Google::Rpc::ErrorInfo.new(reason: "MISSING_TENANT", domain: "shop"))
  end
  order = @db_model.create(request.item)
  Shop::Order.new(id: order.id, item: order.item)
end
```

## Returning an Error

A handler reports an application failure by raising a
[`MeshError`](mesherror.md). The per-code subclasses, such as `NotFoundError`
and `InvalidArgumentError`, take the message and any detail messages.
`MeshError.new(code, message, *details)` takes any `Google::Rpc::Code`.

```ruby
def place(request)
  unless @db_model.in_stock?(request.item)
    raise GrpcServiceMesh::NotFoundError.new("no such item",
      Google::Rpc::ErrorInfo.new(reason: "ITEM_MISSING", domain: "shop"))
  end
  order = @db_model.create(request.item)
  Shop::Order.new(id: order.id, item: order.item)
end
```

A `MeshError` becomes a reply whose payload is the encoded
`Google::Rpc::Status` and whose metadata carries `Grpc-Status`, the code as a
decimal integer string, beside `Content-Type`.

Any other `StandardError`, including a response that is not an instance of the
rpc method's output class, is reported the same way as `UNKNOWN` (2), with the
failure's message.

A request that does not decode is reported as `INTERNAL` (13), the code every
decoding failure carries, and the method is not called. The message names the
message type, such as `request does not decode as shop.Order: ...`.

In the Service Mesh API, an endpoint handler returns a reply message or raises,
and a transport reports a raised error to the caller in its own way. The
endpoint that `RPCService` builds always returns a reply message, even for a
failure. A caller therefore receives every handler failure as a `MeshError`,
and never as the transport's own handler error.

## Reply Metadata

A `ROUTE` handler sets metadata on its reply through the `mesh_metadata` of the
response it returns. When it raises a `MeshError`, the reply's metadata is the
error's `mesh_metadata`, which the error takes on construction as
`mesh_metadata:` or through `mesh_metadata=`. The `UNKNOWN` reply for any other
failure carries only the library's keys.

The library writes `Content-Type` and `Grpc-Status` over the application's
values, so its own values win, and a successful reply carries no
`Grpc-Status`. Keys that start with `Mesh-Option-` are removed from the reply's
metadata.

```ruby
def place(request)
  unless @db_model.in_stock?(request.item)
    raise GrpcServiceMesh::NotFoundError.new("no such item", mesh_metadata: {"Retry-After" => "30"})
  end
  record = @db_model.create(request.item)
  order = Shop::Order.new(id: record.id, item: record.item)
  order.mesh_metadata["Request-Id"] = "7"
  order
end
```

## Subscriber Handlers

A `TOPIC` handler receives the decoded message, and its return value is ignored.
A `TOPIC` message has no reply, so metadata the handler sets goes nowhere.

The subscriber that `RPCService` builds lets an exception from the handler
propagate to the transport unchanged. The transport documents what it does
with it.

A message that does not decode is handled the same way. The method is not
called, and the transport receives a `Google::Protobuf::ParseError` that names
the message type, such as `request does not decode as shop.Order: ...`.

## Message Metadata

Message metadata travels on the message objects themselves. The generated
code includes the `GrpcServiceMesh::Metadata` module into every message class
that an rpc method takes or returns. The module adds two methods.

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
