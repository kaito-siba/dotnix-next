{
  # 任意の systemd サービスを lease でオンデマンド起動し、WoL で起こされた仕事が終わったら
  # suspend する。仕組みと API は ./agent.py の docstring を参照。クライアントの認証は
  # tailscale whois のノード名で行う (鍵の配布は不要)。
  # 対象のサービス自体は普通に systemd.services で定義し、wantedBy を付けないこと。
  flake.modules.nixos.wake-lease =
    { config, lib, pkgs, ... }:
    let
      cfg = config.wake-lease;
      service =
        { name, ... }:
        {
          options = {
            unit = lib.mkOption {
              type = lib.types.str;
              default = "${name}.service";
              description = "lease がある間だけ動かす unit";
            };
            healthUrl = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "起動完了の確認に使う URL (null なら unit が active になった時点)";
            };
            startTimeout = lib.mkOption {
              type = lib.types.int;
              default = 300;
              description = "起動完了を待つ秒数";
            };
            allowedNodes = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              example = [ "twit-curator" ];
              description = "このサービスの lease を取れる tailnet のノード名";
            };
          };
        };
      config' = pkgs.writeText "wake-lease.json" (
        builtins.toJSON {
          inherit (cfg) port;
          services = lib.mapAttrs (_: s: {
            inherit (s) unit;
            health_url = s.healthUrl;
            start_timeout = s.startTimeout;
            allowed_nodes = s.allowedNodes;
          }) cfg.services;
        }
      );
    in
    {
      options.wake-lease = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8089;
          description = "API のポート (tailscale0 でだけ開ける)";
        };
        services = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule service);
          default = { };
          description = "lease で起動するサービス (キーが API のサービス名)";
        };
      };

      config = lib.mkIf (cfg.services != { }) {
        systemd.services.wake-lease = {
          description = "On-demand services with leases, suspend after Wake-on-LAN work";
          wantedBy = [ "multi-user.target" ];
          after = [ "tailscaled.service" ];
          # systemctl / loginctl / busctl / tailscale / nvidia-smi
          path = [ "/run/current-system/sw" ];
          environment.WAKE_LEASE_CONFIG = config';
          serviceConfig = {
            ExecStart = "${pkgs.python3}/bin/python3 ${./agent.py}";
            Restart = "always";
          };
        };

        networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];
      };
    };
}
