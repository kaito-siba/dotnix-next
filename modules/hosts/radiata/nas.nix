{
  # NAS (copyparty) を WebDAV 経由で /mnt/nas に rclone mount する。
  # 認証情報は ./secrets/nas.yaml (sops, radiata の host key で復号)。
  # pass は `rclone obscure <password>` した値を入れる。
  flake.modules.nixos."hosts/radiata" =
    { config, pkgs, ... }:
    {
      # mount.rclone ヘルパーを PATH に置く
      environment.systemPackages = [ pkgs.rclone ];

      sops.secrets = {
        "nas/user".sopsFile = ./secrets/nas.yaml;
        "nas/pass".sopsFile = ./secrets/nas.yaml;
      };

      # copyparty 推奨設定: vendor=owncloud で mtime を保持、pacer を短縮
      sops.templates."rclone-nas.conf".content = ''
        [nas]
        type = webdav
        url = https://file.home.umitonelab.com
        vendor = owncloud
        pacer_min_sleep = 0.01ms
        user = ${config.sops.placeholder."nas/user"}
        pass = ${config.sops.placeholder."nas/pass"}
      '';

      fileSystems."/mnt/nas" = {
        device = "nas:";
        fsType = "rclone";
        options = [
          "nodev"
          "nofail"
          "_netdev"
          "noauto"
          "x-systemd.automount"
          "x-systemd.idle-timeout=600"
          "x-systemd.after=network-online.target"
          "x-systemd.requires=network-online.target"
          "allow_other"
          "uid=1000" # rkv12 (uid は宣言されていないため実値)
          "gid=${toString config.users.groups.users.gid}"
          "args2env"
          "config=${config.sops.templates."rclone-nas.conf".path}"
          "cache_dir=/var/cache/rclone"
          "vfs_cache_mode=writes"
          "dir_cache_time=1m"
        ];
      };
    };
}
