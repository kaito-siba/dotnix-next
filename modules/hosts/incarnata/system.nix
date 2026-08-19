{ config, ... }:
{
  # No networking.* for this host: its hostname is managed outside this repo,
  # so nix deliberately leaves it alone. Because of that the flake attribute
  # cannot match the real hostname, and darwin-rebuild needs it spelled out:
  #
  #   sudo darwin-rebuild switch --flake .#incarnata
  flake.modules.darwin."hosts/incarnata" = {
    nixpkgs.hostPlatform = "aarch64-darwin";

    system.primaryUser = config.flake.meta.users.k-nanchi.username;
  };
}
