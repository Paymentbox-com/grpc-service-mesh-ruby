# frozen_string_literal: true

require_relative "lib/grpc_service_mesh/version"

Gem::Specification.new do |spec|
  spec.name = "grpc_service_mesh"
  spec.version = GrpcServiceMesh::VERSION
  spec.authors = ["Bryant Morrill", "Paymentbox"]
  spec.email = ["bmorrill@pmtbox.com"]
  spec.summary = "Ruby library for the gRPC Service Mesh API"
  spec.homepage = "https://github.com/Paymentbox-com/grpc-service-mesh-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE]
  spec.require_paths = ["lib"]

  spec.add_dependency "google-protobuf", "~> 4.26"
  spec.add_dependency "googleapis-common-protos-types", "~> 1.15"
  spec.add_dependency "service_mesh", "~> 0.4"
end
