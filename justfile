# Task runner for grpc_service_mesh. Run `just` with no arguments to see the menu.
#
# Every Ruby recipe runs through `mise exec` so it uses the Ruby pinned in
# mise.toml without relying on the shell's mise activation. If you run just from
# a bare environment where `mise` is not on PATH, change this to
# "/opt/homebrew/bin/mise exec -- bundle".
bundle := "mise exec -- bundle"

# The version in the gemspec, which names the built gem file
version := `mise exec -- ruby -e 'print Gem::Specification.load("grpc_service_mesh.gemspec").version'`
protoc := env("PROTOC", "protoc")

# List all recipes
default:
    @just --list

# Install gem dependencies
[group('build')]
install:
    {{bundle}} install

# Run the test suite
[group('build')]
test:
    {{bundle}} exec rspec

# Build the gem into pkg/grpc_service_mesh-<version>.gem
[group('build')]
build:
    mkdir -p pkg
    mise exec -- gem build grpc_service_mesh.gemspec --output pkg/grpc_service_mesh-{{version}}.gem

# Push the built gem to rubygems.org; asks for the MFA code
[group('release')]
publish:
    mise exec -- gem push pkg/grpc_service_mesh-{{version}}.gem

# Tag the current commit v<version> and push the tag; refuses a working tree with changes
[group('release')]
tag:
    test -z "$(git status --porcelain)" || (echo "commit or stash your changes first" && exit 1)
    git tag -a v{{version}} -m "v{{version}}"
    git push origin v{{version}}

# Tag the current commit, build the gem, and push it to rubygems.org
[group('release')]
release: tag build publish

# The grpc-service-mesh-api tag whose mesh/options.proto lib/mesh/options_pb.rb is compiled from
spec_tag := "v0.4.0"

# Regenerate lib/mesh/options_pb.rb from the specification at {{spec_tag}}
# and regenerate the specs' message classes
[group('build')]
proto: proto-spec proto-test

# Compile mesh/options.proto from a shallow clone of grpc-service-mesh-api at {{spec_tag}} into lib/mesh/options_pb.rb
[group('build')]
proto-spec:
    #!/usr/bin/env bash
    set -euo pipefail
    spec="$(mktemp -d)"
    trap 'rm -rf "$spec"' EXIT
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch {{spec_tag}} https://github.com/Paymentbox-com/grpc-service-mesh-api "$spec"
    {{protoc}} --proto_path="$spec" --ruby_out=lib "$spec/mesh/options.proto"

# Regenerate the message classes the specs use from spec/support/testproto
[group('build')]
proto-test:
    {{protoc}} --proto_path=spec/support/testproto --ruby_out=spec/support/testproto spec/support/testproto/shop/order.proto

# Report lint findings (matches CI)
[group('checks')]
lint:
    {{bundle}} exec rubocop

# Fix lint findings in place
[group('checks')]
fmt:
    {{bundle}} exec rubocop -A

# Everything CI checks, in the order CI runs them
[group('checks')]
check: lint test build
