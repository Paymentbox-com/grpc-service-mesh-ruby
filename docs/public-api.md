# Public API

Every public constant and method in `GrpcServiceMesh`.

| Name | Role |
|---|---|
| `GrpcServiceMesh.transport_router` | The process `TransportRouter`, created on first use. |
| `GrpcServiceMesh.add_transport(name, client)` | A shortcut for `transport_router.add`. |
| `GrpcServiceMesh.registry` | The process `Registry`, created on first use. |
| `GrpcServiceMesh.register(service)` | A shortcut for `registry.register`. |
| `GrpcServiceMesh::TransportRouter` | Holds one client per transport name. `TransportRouter.new` builds an empty one. Its methods are `#add(name, client)`, `#client(name)`, `#names`, and `#close`. |
| `GrpcServiceMesh::Registry` | Holds the registered endpoints and subscribers. `Registry.new` builds an empty one. Its methods are `#register(service)`, `#endpoints(deployment_group)`, and `#subscribers(deployment_group)`. |
| `GrpcServiceMesh::RPCService` | The base class of generated services. It defines `.rpc(...)`, `.rpcs`, `#endpoints`, and `#subscribers`. A handler method takes `(request)`. |
| `GrpcServiceMesh::RPCClient` | The base class of generated clients. `.rpc(...)` defines a class method `name(request)` for each rpc, and `.rpcs` lists them. |
| `GrpcServiceMesh::RPCRuntime.new(transport:, deployment_group:, runtime:, config: {}, endpoints: nil, subscribers: nil)` | Builds an `RPCRuntime`, which serves one transport and one deployment group. Its methods are `#start`, `#stop(drain)`, `#running?`, `#client`, `#t_runtime`, `#transport`, and `#deployment_group`. |
| `GrpcServiceMesh::Rpc` | A `Data` value describing one rpc, with `name`, `target`, `input`, `output`, `kind`, `owner`, and `#route?`. |
| `GrpcServiceMesh::Metadata` | A module that adds `#mesh_metadata` and `#mesh_metadata=` to a message class. |
| `GrpcServiceMesh::MeshError` | Described under [MeshError](mesherror.md). `MeshError.new`, `MeshError.from_proto`, and one subclass per code, such as `NotFoundError`, build one. Its methods are `#code`, `#message`, `#details`, `#proto`, and `#mesh_metadata`. |
| `GrpcServiceMesh::OPTION_PREFIX` | `"Mesh-Option-"`, the prefix that marks a metadata key as a transport option. |
| `GrpcServiceMesh::Wire` | Holds the constants `CONTENT_TYPE_KEY`, `CONTENT_TYPE`, and `GRPC_STATUS_KEY`. |
| `GrpcServiceMesh::Error`, `GrpcServiceMesh::UnknownTransport`, `GrpcServiceMesh::CloseFailed` | Listed under [Library Errors](mesherror.md#library-errors). |
