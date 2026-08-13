{
  # Dual boot: Windows lives on its own disk (nvme0n1) with its own ESP, which
  # is where GRUB's os-prober used to find it. systemd-boot has no os-prober
  # equivalent, so that ESP is mounted read-only and the Windows boot files are
  # copied into ours as a menu entry instead.
  flake.modules.nixos."hosts/albiflora" = {
    fileSystems."/mnt/windows-esp" = {
      device = "/dev/disk/by-uuid/AEAE-AB9B";
      fsType = "vfat";
      options = [
        "nofail"
        "ro"
      ];
    };

    boot.loader = {
      timeout = 10;

      systemd-boot.extraEntries = {
        "windows.conf" = ''
          title Windows 11
          efi /EFI/Microsoft/Boot/bootmgfw.efi
          sort-key 0
        '';
      };

      systemd-boot.extraFiles = {
        "EFI/Microsoft/Boot/bootmgfw.efi" = "/mnt/windows-esp/EFI/Microsoft/Boot/bootmgfw.efi";
        "EFI/Microsoft/Boot/BCD" = "/mnt/windows-esp/EFI/Microsoft/Boot/BCD";
      };
    };
  };
}
