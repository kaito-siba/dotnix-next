{
  flake.modules.nixos.virtualisation =
    { pkgs, ... }:
    {
      virtualisation.libvirtd = {
        enable = true;
        qemu = {
          swtpm.enable = true; # Windows 11向けTPM
          vhostUserPackages = with pkgs; [ virtiofsd ]; # 共有フォルダ用
        };
      };

      programs.virt-manager.enable = true;
      virtualisation.spiceUSBRedirection.enable = true;
      networking.firewall.trustedInterfaces = [ "virbr0" ];

      environment.systemPackages = with pkgs; [
        dnsmasq # libvirt default network用
        virtiofsd
      ];
    };
}
