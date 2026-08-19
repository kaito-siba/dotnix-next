{
  # Time tracking: aw-server-rust (patched master, see _overlay.nix) plus the
  # awatcher window/afk watcher and periodic aw-sync of local buckets into
  # ~/ActivityWatchSync.
  #
  # On darwin the server and its window/afk watchers come from the
  # ActivityWatch app instead -- neither is packaged in nixpkgs -- so nix only
  # contributes the periodic aw-sync agent next to it.
  flake.modules.darwin.activitywatch = {
    homebrew.casks = [ "activitywatch" ];
  };

  flake.modules.homeManager.activitywatch =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      # The top-level activitywatch attr is a linux-only wrapper around server
      # and watchers. On darwin only aw-sync is wanted, and the overlay above
      # already unlocks aw-server-rust for that platform, so take the binary
      # straight from there.
      awSyncPackage =
        if pkgs.stdenv.hostPlatform.isDarwin then pkgs.aw-server-rust else pkgs.activitywatch;

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
        exec ${awSyncPackage}/bin/aw-sync sync --mode both --buckets "$buckets"
      '';
    in
    lib.mkMerge [
      {
        nixpkgs.overlays = [ (import ./_overlay.nix) ];
      }

      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
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
      })

      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        launchd.agents.aw-sync = {
          enable = true;
          config = {
            Label = "org.activitywatch.aw-sync-local";
            ProgramArguments = [ "${awSyncLocal}" ];
            StartInterval = 300;
            RunAtLoad = false;
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/aw-sync.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/aw-sync.log";
          };
        };
      })
    ];
}
