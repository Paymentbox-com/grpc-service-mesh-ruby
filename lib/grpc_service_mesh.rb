# frozen_string_literal: true

require "service_mesh"

require_relative "grpc_service_mesh/version"
require_relative "grpc_service_mesh/errors"
require_relative "grpc_service_mesh/wire"
require_relative "grpc_service_mesh/mesh_error"
require_relative "grpc_service_mesh/transport_router"
require_relative "grpc_service_mesh/registry"
require_relative "grpc_service_mesh/rpc"
require_relative "grpc_service_mesh/rpc_service"
require_relative "grpc_service_mesh/rpc_client"
require_relative "grpc_service_mesh/rpc_runtime"

# Ruby library for the gRPC Service Mesh API. Generated code declares rpcs on
# RPCService and RPCClient subclasses; the application configures the process
# TransportRouter, registers its services, and starts an RPCRuntime.
module GrpcServiceMesh
  class << self
    # The process TransportRouter.
    def transport_router
      @transport_router ||= TransportRouter.new
    end

    # The process Registry.
    def registry
      @registry ||= Registry.new
    end

    # Shortcut for transport_router.add.
    def add_transport(name, client)
      transport_router.add(name, client)
    end

    # Shortcut for registry.register.
    def register(service)
      registry.register(service)
    end

    # Merges +metadata+ into the metadata of the reply the running route
    # handler sends. A later call adds keys and overwrites the ones already
    # set. Content-Type and Grpc-Status are set by the library and override
    # values in +metadata+. Outside a route handler it has no effect.
    def set_reply_metadata(metadata)
      Thread.current[RPCService::REPLY_METADATA_KEY]&.merge!(metadata.to_h)
    end
  end
end
