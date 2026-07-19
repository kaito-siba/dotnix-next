{
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
