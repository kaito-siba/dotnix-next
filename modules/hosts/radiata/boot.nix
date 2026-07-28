{
  # Dual boot: /boot is its own ext4 partition with the ESP mounted below it,
  # and the Windows boot files are copied from the Windows ESP into systemd-boot
  # entries so both OSes show up in one menu.
  flake.modules.nixos."hosts/radiata" = {
    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/214968ef-c733-4432-aff8-a5ffab7748f6";
      fsType = "ext4";
    };

    fileSystems."/boot/efi" = {
      device = "/dev/disk/by-uuid/3FC0-A77D";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };

    fileSystems."/mnt/windows-esp" = {
      device = "/dev/disk/by-uuid/4E68-4C1A";
      fsType = "vfat";
      options = [
        "nofail"
        "ro"
      ];
    };

    boot.loader = {
      efi.efiSysMountPoint = "/boot/efi";

      # https://github.com/NixOS/nixpkgs/issues/316285
      grub.enable = false;

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
