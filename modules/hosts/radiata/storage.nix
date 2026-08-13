{
  flake.modules.nixos."hosts/radiata" = {
    fileSystems."/data" = {
      device = "/dev/disk/by-label/radiata-data";
      fsType = "ext4";
      options = [
        "nofail"
        "noatime"
      ];
    };

    systemd.tmpfiles.rules = [
      "d /data 0755 rkv12 users -"
    ];
  };
}
