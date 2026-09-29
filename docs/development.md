# Development

## Specification Protos

`lib/mesh/options_pb.rb` is protoc's Ruby output of the specification's
`mesh/options.proto`. Loading it adds the file to the generated descriptor
pool, which then resolves the extensions `mesh.kind`, `mesh.consumer_group`,
`mesh.deployment_group`, `mesh.transport`, and `mesh.root_prefix`, and defines
`Mesh::Kind`. It is compiled from the
[grpc-service-mesh-api](https://github.com/Paymentbox-com/grpc-service-mesh-api)
tag named by `spec_tag` in the `justfile`.

The compiled forms of `google/rpc/*.proto` are the published ones in
`googleapis-common-protos-types`.

Every `*_pb.rb` file protoc writes from a definitions file that imports
`mesh/options.proto` calls `require 'mesh/options_pb'`, so a definitions
project's Gemfile requires this gem. Plain `protoc` takes the specification's
files from the directory `grpc-service-mesh-gen proto-path` prints:

```sh
protoc \
  -I definitions \
  -I "$(grpc-service-mesh-gen proto-path)" \
  --ruby_out=lib/ruby \
  $(find definitions -name '*.proto')
```

Only files under `definitions/` are listed. The specification's files are
only on the include path. A project that runs this command itself runs the
generator with `--mesh-only`, which writes the mesh code and skips the
message runs.

### Updating the Compiled Specification Protos

`lib/mesh/options_pb.rb` is the compiled form of `mesh/options.proto` in the
specification repository,
[grpc-service-mesh-api](https://github.com/Paymentbox-com/grpc-service-mesh-api),
at the tag `spec_tag` names in the `justfile`. It is never edited here.
`just proto-spec` makes a shallow clone of that tag in a temporary directory,
compiles `mesh/options.proto` from it with `protoc`, and removes the clone. CI
runs `just proto` and fails when the result differs from what is committed, so
the compiled form always matches the stated tag.

The specification's protobuf definitions maintain backwards compatibility, so
a new specification tag only adds options or enum values. To adopt one:

1. Set `spec_tag` in the `justfile` to the new tag.
2. Run `just proto`.
3. Review the diff under `lib/mesh/`.
4. Run `just check`.
5. Bump the version in `lib/grpc_service_mesh/version.rb`, commit, and run
   `just tag`.

The extension numbers in `mesh/options.proto` are part of every definitions
project's compiled descriptors, and the specification never changes or
reuses one.

## Tools and Tests

```
mise install
just install
just check      # lint, test, build
```

Tool versions are pinned in `mise.toml`. `just` with no arguments lists the recipes.

| Recipe | What it does |
|---|---|
| `just install` | Installs the gem's dependencies with Bundler. |
| `just test` | Runs the test suite. |
| `just build` | Builds the gem into `pkg/grpc_service_mesh-<version>.gem`. |
| `just proto` | Runs `just proto-spec` and `just proto-test`. |
| `just proto-spec` | Compiles `mesh/options.proto` from grpc-service-mesh-api at `spec_tag` into `lib/mesh/options_pb.rb`. |
| `just proto-test` | Regenerates `spec/support/testproto/shop/order_pb.rb` with `protoc`. |
| `just lint` | Reports lint findings with RuboCop. |
| `just fmt` | Fixes lint findings in place with RuboCop. |
| `just check` | Runs `lint`, `test`, and `build`, in the order CI runs them. |
| `just tag` | Tags the current commit with the gem's version and pushes the tag. |
| `just publish` | Pushes the built gem to rubygems.org. |
| `just release` | Runs `tag`, `build`, and `publish`. |

Publishing is described in [publishing.md](../publishing.md).

The tests run against `spec/support/memory_transport.rb`, an in-process
transport. Its client records what it was given, and its runtime subscribes on
the client's in-memory bus and closes the client on stop. It raises
`ServiceMesh::KindMismatch` when a target of the wrong kind is used, so nothing
in this repository needs a broker.

`spec/support/testproto/` holds the `shop.Order` message, its protoc output,
and the reference generated files shown under
[Generated Code](generated-code.md). `just proto-test` regenerates the message
code.

`spec/mesh_options_spec.rb` checks that the five extensions are in the
descriptor pool by their full names.

`spec/spec_helper.rb` gives every example an empty process router and
registry, by replacing both before each example.
