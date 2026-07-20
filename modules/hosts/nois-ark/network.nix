{ config, ... }:
{
  flake.modules.nixos."hosts/nois-ark" = {
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ config.services.searx.serverPort ];
  };
}
