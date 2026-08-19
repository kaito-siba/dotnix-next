{ config, ... }:
{
  # No networking.* for this host: its
  # hostname is managed outside this repo, so nix deliberately leaves it alone.
  # The flake attribute matches that hostname so darwin-rebuild resolves the
  # configuration without an explicit --flake argument.
  flake.modules.darwin."hosts/incarnata" = {
    nixpkgs.hostPlatform = "aarch64-darwin";

    system.primaryUser = config.flake.meta.users.k-nanchi.username;
  };
}
