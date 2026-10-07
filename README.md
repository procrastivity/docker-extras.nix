# docker-extras.nix

A small Nix flake that packages
[docker-extras](https://github.com/procrastivity/docker-extras), the
`docker extras` Docker CLI plugin, from its **prebuilt release archives**. It
gives you `nix build`, `nix run`, an overlay, and a home-manager module that
makes `docker extras` work.

## Why this repo exists

A flake cannot pin the SHA-256 of a release archive inside the same tagged
commit that the archive is built from. The tag freezes its tree before the
archive exists. docker-extras.nix keeps the pin in a separate repo, as
[duo.nix](https://github.com/procrastivity/duo.nix) does:

- a committed [`VERSION.json`](./VERSION.json) (pure eval)
- an `update.sh` that prefetches the **already-published** archives
- a scheduled workflow that commits and tags when the version changes

Nobody builds docker-extras from source, and the packaged version always
matches a published release.

## Packaging model

- Each docker-extras release publishes one `docker-extras-<os>-<arch>.tar.gz`
  per system, holding `plugin/docker-extras` and `LICENSE`, plus a
  `SHA256SUMS` file.
- `VERSION.json` holds the release tag, and the archive URL and SHA-256 hash
  for each system. Nix verifies the hash on every build. `update.sh` also
  refuses any hash that does not match the release's `SHA256SUMS`.
- The binary is a static Go build. It is installed byte-for-byte, with no
  patchelf and no wrapper, and it runs on any Linux host, NixOS included.
  `meta.sourceProvenance` is `binaryNativeCode`.
- Package layout:
  - `libexec/docker/cli-plugins/docker-extras`: the Docker CLI plugin
  - `bin/docker-extras`: the same binary, for `nix run` and direct calls
  - `share/licenses/docker-extras/LICENSE`

### Supported systems

`aarch64-darwin`, `aarch64-linux`, `x86_64-linux`.

> **No `x86_64-darwin`.** docker-extras publishes an Intel-macOS archive, but
> nixpkgs 26.11 (the `nixos-unstable` input here) dropped `x86_64-darwin`. On
> Intel macOS, use the docker-extras installer script from the
> [release page](https://github.com/procrastivity/docker-extras/releases/latest).

## Docker plugin discovery

Docker looks for CLI plugins in `~/.docker/cli-plugins` (or
`$DOCKER_CONFIG/cli-plugins`), not on `PATH`. So installing the package alone
does not give you `docker extras`. Use the home-manager module, or link the
plugin yourself.

### home-manager

```nix
# flake.nix
{
  inputs.docker-extras.url = "github:procrastivity/docker-extras.nix";
  # ...
}

# home.nix (with inputs passed as extraSpecialArgs)
{ inputs, ... }:
{
  imports = [ inputs.docker-extras.homeManagerModules.default ];

  programs.docker-extras.enable = true;
}
```

| Option | Default | Meaning |
| --- | --- | --- |
| `programs.docker-extras.enable` | `false` | link the plugin into the Docker plugin directory |
| `programs.docker-extras.package` | this flake's package | the package to link |
| `programs.docker-extras.pluginName` | `"extras"` | Docker command name: `"tools"` gives `docker tools` |
| `programs.docker-extras.dockerConfigDir` | `".docker"` | Docker config directory, relative to home; change it only when `DOCKER_CONFIG` points elsewhere |

The binary takes its command name from its own file name, so `pluginName`
only changes the link name.

### By hand

```sh
nix build github:procrastivity/docker-extras.nix
mkdir -p ~/.docker/cli-plugins
ln -sf "$(readlink -f result)/libexec/docker/cli-plugins/docker-extras" ~/.docker/cli-plugins/docker-extras
docker extras volume seed --help
```

## Run

```sh
nix run github:procrastivity/docker-extras.nix -- volume seed --help
```

## Overlay

```nix
{ inputs, ... }:
{
  nixpkgs.overlays = [ inputs.docker-extras.overlays.default ];
  # pkgs.docker-extras is now available
}
```

## Updating

`./update.sh` asks GitHub for the latest stable `vX.Y.Z` release of
docker-extras. When it differs from `rev` in `VERSION.json`, the script:

1. downloads the release's `SHA256SUMS`;
2. prefetches each archive and checks its hash against `SHA256SUMS`;
3. writes `VERSION.json`;
4. builds the host package (`nix build .#docker-extras`).

When nothing changed, it does nothing. It works without authentication, but it
uses `GITHUB_TOKEN` when that is set, to avoid rate limits.

The [`.github/workflows/cron.yml`](./.github/workflows/cron.yml) workflow runs
`update.sh` daily (and on manual dispatch). It commits and pushes an annotated
tag only when the version changes.
