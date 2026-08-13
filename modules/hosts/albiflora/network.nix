{
  flake.modules.nixos."hosts/albiflora" = {
    networking = {
      interfaces.enp129s0 = {
        wakeOnLan.enable = true;
      };

      firewall = {
        allowedUDPPorts = [ 9 ]; # wake-on-lan magic packets

        # 445: SMB share served by a container on this host
        allowedTCPPorts = [ 445 ];

        interfaces."tailscale0".allowedTCPPorts = [ 8181 ];
      };
    };
  };
}
