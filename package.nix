{
  lib,
  stdenvNoCC,
  fetchurl,
  version,
  asset,
}:
# Each docker-extras release publishes one tarball per system holding
# plugin/docker-extras and LICENSE. The binary is a static Go build
# (CGO_ENABLED=0), so it needs no loader, no patchelf, and no runtime wrapper on
# any host, NixOS included. We install it byte-for-byte: dontFixup keeps the
# fixup phase from stripping or patching it.
#
# Docker discovers CLI plugins by directory, not on PATH, so the plugin lives at
# libexec/docker/cli-plugins/docker-extras. The homeManagerModules.default
# module links it into ~/.docker/cli-plugins. bin/docker-extras is the same
# binary, for `nix run` and direct calls (`docker-extras volume seed --help`).
stdenvNoCC.mkDerivation {
  pname = "docker-extras";
  inherit version;

  src = fetchurl { inherit (asset) url hash; };
  # The tarball has two top-level entries (plugin/ and LICENSE), not one
  # directory, so unpack in place.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 plugin/docker-extras $out/libexec/docker/cli-plugins/docker-extras
    mkdir -p $out/bin
    ln -s $out/libexec/docker/cli-plugins/docker-extras $out/bin/docker-extras
    install -Dm644 LICENSE $out/share/licenses/docker-extras/LICENSE
    runHook postInstall
  '';

  meta = {
    description = "Small docker-* developer-experience utilities, as a Docker CLI plugin (prebuilt release binary)";
    homepage = "https://github.com/procrastivity/docker-extras";
    license = lib.licenses.mit;
    mainProgram = "docker-extras";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
