{
  # herdr の pane focus と Claude Code エージェント稼働を ActivityWatch に
  # 記録する (aw-watcher-tmux の後継)。herdr が起動していない間は
  # ポーリングを続けるだけで無害。
  flake.modules.homeManager.activitywatch =
    { pkgs, config, ... }:
    let
      awWatcherHerdr = pkgs.writeShellScript "aw-watcher-herdr" ''
        exec ${pkgs.python3}/bin/python3 ${./aw-watcher-herdr.py}
      '';
    in
    {
      systemd.user.services.aw-watcher-herdr = {
        Unit = {
          Description = "Report herdr pane focus and Claude Code agent activity to ActivityWatch";
          After = [ "activitywatch.service" ];
        };

        Service = {
          Type = "simple";
          ExecStart = "${awWatcherHerdr}";
          Restart = "always";
          RestartSec = 10;
          Environment = [
            "HERDR_SOCKET_PATH=${config.xdg.configHome}/herdr/herdr.sock"
            "AW_URL=http://127.0.0.1:5600"
            "POLL_INTERVAL=10"
          ];
        };

        Install = {
          WantedBy = [ "activitywatch.target" ];
        };
      };
    };
}
