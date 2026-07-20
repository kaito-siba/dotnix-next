{ config, ... }:
{
  flake.modules.darwin."hosts/squamigera" = {
    nixpkgs.hostPlatform = "aarch64-darwin";

    system.primaryUser = config.flake.meta.users.w963n.username;
  };
}
