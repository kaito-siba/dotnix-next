{
  # Time tracking: aw-server-rust (patched master, see _overlay.nix) plus the
  # awatcher window/afk watcher and periodic aw-sync of local buckets into
  # ~/ActivityWatchSync.
  flake.modules.homeManager.activitywatch =
    { pkgs, config, ... }:
    let
      awSyncLocal = pkgs.writeShellScript "aw-sync-local" ''
        set -euo pipefail
        buckets=$(${pkgs.curl}/bin/curl -sf http://127.0.0.1:5600/api/0/buckets/ \
          | ${pkgs.jq}/bin/jq -r 'to_entries
              | map(select(.value.data["$aw.sync.origin"] == null))
              | map(.key) | join(",")')
        if [ -z "$buckets" ]; then
          echo "aw-sync-local: no local buckets found, skipping" >&2
          exit 0
        fi
        exec ${pkgs.activitywatch}/bin/aw-sync sync --mode both --buckets "$buckets"
      '';
    in
    {
      nixpkgs.overlays = [ (import ./_overlay.nix) ];

      services.activitywatch = {
        enable = true;
        watchers = { };
      };

      home.packages = [
        pkgs.awatcher
      ];

      systemd.user.services.awatcher = {
        Unit = {
          Description = "Awatcher for ActivityWatch";
          After = [
            "graphical-session.target"
            "activitywatch.service"
          ];
          Wants = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };

        Service = {
          Type = "simple";
          ExecStart = "${pkgs.awatcher}/bin/awatcher";
          Restart = "on-failure";
          RestartSec = 5;
          Environment = [
            "XDG_RUNTIME_DIR=/run/user/%U"
          ];
        };

        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };

      systemd.user.services.aw-sync = {
        Unit = {
          Description = "aw-sync for ActivityWatch (local buckets only)";
          After = [ "activitywatch.service" ];
          Requires = [ "activitywatch.service" ];
        };

        Service = {
          Type = "oneshot";
          ExecStart = "${awSyncLocal}";
        };
      };

      systemd.user.timers.aw-sync = {
        Unit = {
          Description = "Run aw-sync periodically";
        };

        Timer = {
          OnBootSec = "2min";
          OnUnitActiveSec = "5min";
          Unit = "aw-sync.service";
        };

        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    };
}
