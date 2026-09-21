# frozen_string_literal: true

require "grpc_service_mesh"
require_relative "support/memory_transport"
require_relative "support/testproto/service_maps"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.before { GrpcServiceMesh.reset! }
end
