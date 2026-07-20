{
  # On darwin the App Store flavored app carries the network extension, which
  # nothing built from nixpkgs can provide.
  flake.modules.darwin.tailscale = {
    homebrew.casks = [ "tailscale-app" ];
  };

  flake.modules.nixos.tailscale = {
    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "client";
      extraUpFlags = [ "--accept-dns=true" ];
      extraSetFlags = [
        "--ssh"
        "--operator=$USER"
      ];
    };
  };
}
