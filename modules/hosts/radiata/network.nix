{
  flake.modules.nixos."hosts/radiata" = {
    networking = {
      interfaces.enp4s0 = {
        wakeOnLan.enable = true;
      };
      firewall = {
        allowedUDPPorts = [ 9 ]; # wake-on-lan magic packets

        # 8790: dennotai, 7860: kotoba-whisper-gui
        interfaces."tailscale0".allowedTCPPorts = [
          8790
          7860
        ];
      };
    };
  };
}
