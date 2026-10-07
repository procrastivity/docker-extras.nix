{
  description = "docker-extras.nix — prebuilt docker-extras Docker CLI plugin packaging";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      # The pinned release tag and per-system asset URL + SHA-256 hash live in
      # VERSION.json (pure eval). update.sh re-pins it on each release; the
      # flake never hard-codes a version.
      versionData = builtins.fromJSON (builtins.readFile ./VERSION.json);
      version = nixpkgs.lib.removePrefix "v" versionData.rev;

      # Supported systems are exactly the keys present in VERSION.json, so
      # adding a platform is a data-only change.
      supportedSystems = builtins.attrNames versionData.systems;

      forEachSystem = nixpkgs.lib.genAttrs supportedSystems;

      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      packages = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
          asset = versionData.systems.${system} or (throw "docker-extras.nix: unsupported system ${system}");
          docker-extras = pkgs.callPackage ./package.nix {
            inherit version asset;
          };
        in
        {
          inherit docker-extras;
          default = docker-extras;
        }
      );

      formatter = forEachSystem (system: (pkgsFor system).nixfmt);

      overlays = {
        default = _final: prev: {
          docker-extras = self.packages.${prev.stdenv.hostPlatform.system}.docker-extras;
        };
      };

      homeManagerModules = {
        docker-extras = import ./home-manager.nix self;
        default = self.homeManagerModules.docker-extras;
      };
    };
}
