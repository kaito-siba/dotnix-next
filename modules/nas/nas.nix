{
  # NAS (copyparty) を WebDAV 経由で /mnt/nas に rclone mount する。
  # 認証情報は ./secrets/nas.yaml (sops, 各ホストの host key で復号)。
  # pass は `rclone obscure <password>` した値を入れる。
  flake.modules.nixos.nas =
    { config, lib, pkgs, ... }:
    {
      options.nas.uid = lib.mkOption {
        type = lib.types.int;
        description = "/mnt/nas のファイルの所有者にする uid (ユーザーの uid は宣言されていないため実値を入れる)";
      };

      config = {
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
            "uid=${toString config.nas.uid}"
            "gid=${toString config.users.groups.users.gid}"
            "args2env"
            "config=${config.sops.templates."rclone-nas.conf".path}"
            "cache_dir=/var/cache/rclone"
            "vfs_cache_mode=writes"
            "dir_cache_time=1m"
          ];
        };
      };
    };
}
