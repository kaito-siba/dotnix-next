{
  # tailscaled from nixpkgs on both platforms. On darwin this replaces the
  # App Store app: the network extension it carries only matters for the GUI,
  # and the open-source daemon is what Tailscale SSH needs anyway. nixpkgs
  # tracks upstream releases on both platforms at the same pace, where the
  # App Store build waits for Apple review.
  #
  # nix-darwin's module only starts the daemon; the node flags are set once
  # by hand (they persist in /var/lib/tailscale):
  #   sudo tailscale up --ssh --operator=$USER --accept-routes --accept-dns=true
  flake.modules.darwin.tailscale = {
    services.tailscale.enable = true;
  };

  flake.modules.nixos.tailscale = {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "client";
      extraSetFlags = [
        "--ssh"
        "--operator=$USER"
        "--accept-routes"
        "--accept-dns=true"
      ];
    };
  };
}
