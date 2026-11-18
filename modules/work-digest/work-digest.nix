{
  # 仕事用の常駐機で、Slack の sweep と standup の下書きを定期的に作り、HTTP で
  # 読めるようにする。仕組みと API は ./agent.py の docstring を参照。
  # 中身は headless の Claude Code (claude -p) で、その user の login と claude.ai
  # の Slack connector を使う。なので system ではなく user の unit として動かす。
  # 読む側は herdr-app の inbox mod (この machine と、tailnet の他の machine)。
  # クライアントの認証は tailscale whois のノード名で行う (wake-lease と同じ)。
  #
  # 入れる host では両方の module を取り込み、nixos 側で user を、home-manager
  # 側で読ませるノードを決める。
  flake.modules.nixos.work-digest =
    { config, lib, ... }:
    let
      cfg = config.work-digest;
    in
    {
      options.work-digest = {
        user = lib.mkOption {
          type = lib.types.str;
          description = "work-digest を動かす user";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 8792;
          description = "API のポート (tailscale0 でだけ開ける)。home-manager 側の port と揃える";
        };
      };

      config = {
        networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];

        # logout している間も timer と API を動かす。
        users.users.${cfg.user}.linger = true;
      };
    };

  flake.modules.homeManager.work-digest =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.work-digest;
      config' = pkgs.writeText "work-digest.json" (
        builtins.toJSON {
          inherit (cfg) port;
          allowed_nodes = cfg.allowedNodes;
          sweep_model = cfg.sweepModel;
          standup_model = cfg.standupModel;
          cutover_hour = cfg.cutoverHour;
        }
      );
      agent = command: "${pkgs.python3}/bin/python3 ${./agent.py} ${command}";
      # claude / gh は user の profile、tailscale / systemctl は system の物を使う。
      environment = [
        "WORK_DIGEST_CONFIG=${config'}"
        "PATH=${config.home.profileDirectory}/bin:/run/wrappers/bin:/run/current-system/sw/bin"
      ];
      job = description: command: {
        Unit.Description = description;
        Service = {
          Type = "oneshot";
          ExecStart = agent command;
          # claude -p は既定で claude.ai の connector がつながる前に最初の turn を送り、その turn の model には Slack の tool が見えない。
          Environment = environment ++ [ "MCP_CONNECTION_NONBLOCKING=false" ];
        };
      };
      timer = description: calendar: {
        Unit.Description = description;
        Timer = {
          OnCalendar = calendar;
          # 止まっていた間に過ぎた分は、起動した時に 1 回だけ走らせる。
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    in
    {
      options.work-digest = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8792;
          description = "API のポート";
        };
        allowedNodes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "incarnata" ];
          description = "API を読める tailnet のノード名 (この machine 自身は loopback で常に読める)";
        };
        sweepCalendar = lib.mkOption {
          type = lib.types.str;
          default = "Mon..Fri *-*-* 09..19:00:00";
          description = "Slack の sweep を走らせる時刻 (systemd の OnCalendar)";
        };
        standupCalendar = lib.mkOption {
          type = lib.types.str;
          default = "Mon..Fri *-*-* 23:00:00";
          description = "standup の下書きを書く時刻 (systemd の OnCalendar)";
        };
        cutoverHour = lib.mkOption {
          type = lib.types.ints.between 0 23;
          default = 18;
          description = "standup の対象の日が切り替わる時刻。これより前は前の営業日、後は当日を書く";
        };
        sweepModel = lib.mkOption {
          type = lib.types.str;
          default = "sonnet";
          description = "Slack の sweep に使う model";
        };
        standupModel = lib.mkOption {
          type = lib.types.str;
          default = "sonnet";
          description = "standup の下書きに使う model";
        };
      };

      config = {
        systemd.user.services.work-digest = {
          Unit.Description = "Slack sweep and standup draft API";
          Service = {
            ExecStart = agent "serve";
            Environment = environment;
            Restart = "always";
            RestartSec = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };

        systemd.user.services.work-digest-sweep = job "Sweep Slack for asks and FYIs" "sweep";
        systemd.user.timers.work-digest-sweep = timer "Sweep Slack on work hours" cfg.sweepCalendar;

        systemd.user.services.work-digest-standup = job "Draft the standup answer" "standup";
        systemd.user.timers.work-digest-standup = timer "Draft the standup in the evening" cfg.standupCalendar;
      };
    };
}
