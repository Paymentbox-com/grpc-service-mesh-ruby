# Task runner for grpc_service_mesh. Run `just` with no arguments to see the menu.
#
# Every Ruby recipe runs through `mise exec` so it uses the Ruby pinned in
# mise.toml without relying on the shell's mise activation. If you run just from
# a bare environment where `mise` is not on PATH, change this to
# "/opt/homebrew/bin/mise exec -- bundle".
bundle := "mise exec -- bundle"
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

# Build the gem into pkg/
[group('build')]
build:
    mkdir -p pkg
    mise exec -- gem build grpc_service_mesh.gemspec --output pkg/grpc_service_mesh.gem

# Regenerate the message classes the specs use from spec/support/testproto
[group('build')]
proto:
    {{protoc}} --proto_path=spec/support/testproto --ruby_out=spec/support/testproto spec/support/testproto/pbx/api_key.proto

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
