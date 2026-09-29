# Publishing

`grpc_service_mesh` is published to [rubygems.org](https://rubygems.org/gems/grpc_service_mesh) by hand
from a local checkout. The account that pushes is an owner of the gem, and
rubygems.org asks for its MFA code on every push because the gemspec sets
`rubygems_mfa_required`.

This gem depends on `service_mesh`. A release that needs a newer `service_mesh` is published after that `service_mesh` version is on rubygems.org, since `gem push` accepts the gem either way but `bundle install` fails for anyone installing it until the dependency exists.

## One-Time Setup

```sh
gem signin
```

This stores an API key in `~/.gem/credentials`.

## Releasing a Version

1. Run `just bump patch`, `just bump minor`, or `just bump major` to set the new
   version in `lib/grpc_service_mesh/version.rb` and commit that file, then push `master`.
2. Wait for CI on `master` to pass.
3. Run the release from that commit:

   ```sh
   just release
   ```

   `just release` runs three recipes in order. `just tag` tags the commit
   `vX.Y.Z` and pushes the tag, and refuses when the working tree has
   changes. `just build` writes `pkg/grpc_service_mesh-X.Y.Z.gem`. `just publish` pushes
   that file and prompts for the MFA code. When the push fails after the tag
   exists, `just publish` alone retries it.

A pushed version is permanent. It can be yanked with `gem yank grpc_service_mesh -v X.Y.Z`,
but that version number can never be pushed again.

## Adding an Owner

```sh
gem owner grpc_service_mesh --add someone@example.com
```
