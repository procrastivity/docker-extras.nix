# Home-manager module: link the docker-extras plugin into Docker's per-user
# plugin directory. Docker finds CLI plugins there, not on PATH, so installing
# the package alone does not give you `docker extras`.
#
# The binary takes its command name from its own file name
# (docker-<name> → `docker <name>`), so pluginName only changes the link name.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.docker-extras;
in
{
  options.programs.docker-extras = {
    enable = lib.mkEnableOption "the docker-extras Docker CLI plugin";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.docker-extras;
      defaultText = lib.literalExpression "docker-extras.packages.\${pkgs.stdenv.hostPlatform.system}.docker-extras";
      description = "The docker-extras package to link into the Docker plugin directory.";
    };

    pluginName = lib.mkOption {
      # Docker's own rule for a plugin name.
      type = lib.types.strMatching "[a-z][a-z0-9]*";
      default = "extras";
      example = "tools";
      description = "Docker command name for the plugin: `docker <pluginName>`.";
    };

    dockerConfigDir = lib.mkOption {
      type = lib.types.str;
      default = ".docker";
      description = ''
        Docker config directory, relative to the home directory. Change it only
        when DOCKER_CONFIG points somewhere else.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file."${cfg.dockerConfigDir}/cli-plugins/docker-${cfg.pluginName}".source =
      "${cfg.package}/libexec/docker/cli-plugins/docker-extras";
  };
}
