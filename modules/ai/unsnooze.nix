{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      unsnooze = pkgs.buildNpmPackage rec {
        pname = "unsnooze";
        version = "1.14.0";

        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
          hash = "sha256-mdDtGrgf+6ZmXlDkipt1ql0tMUK5HsFkms/DM184B0c=";
        };

        npmDepsHash = "sha256-LpJkIN/Il37VjvttBeBy/HdiWIFWcC5jLjMnoQnpdiE=";

        # herdr multiplexer backend (upstream 1.14.0 には未収録)。依存関係には
        # 触れないので npmDepsHash と package-lock はそのままで良い。
        patches = [ ./unsnooze-herdr.patch ];

        postPatch = ''
          cp ${
            pkgs.fetchurl {
              url = "https://raw.githubusercontent.com/saaranshM/unsnooze/v${version}/package-lock.json";
              hash = "sha256-1K9vOWR6XF2yODcd3XrpqUWpfDU0ycFVfLoACmHy2OM=";
            }
          } package-lock.json
        '';

        dontNpmBuild = true;

        nativeBuildInputs = [ pkgs.makeWrapper ];

        postInstall = ''
          wrapProgram $out/bin/unsnooze \
            --prefix PATH : ${
              lib.makeBinPath [
                pkgs.nodejs_24
                pkgs.tmux
              ]
            }
        '';
      };

      daemonPath = lib.makeBinPath [
        unsnooze
        pkgs.nodejs_24
        pkgs.tmux
        pkgs.coreutils
        pkgs.bash
        pkgs.zsh
      ];
    in
    {
      home.packages = [ unsnooze ];
      home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

      # `home-manager.useUserPackages` normally links home.packages during the
      # root NixOS switch. Keep the CLI available after a user-only activation too.
      home.file.".local/bin/unsnooze".source = "${unsnooze}/bin/unsnooze";

      # Unsnooze is pinned by Nix, so its npm self-update check is deliberately
      # disabled. Claude and Codex are the two agents installed by this profile.
      home.sessionVariables = {
        # auto: herdr ペイン内では herdr、tmux ペイン内では従来どおり tmux を選ぶ
        UNSNOOZE_MULTIPLEXER = "auto";
        UNSNOOZE_UPDATE_CHECK = "0";
        UNSNOOZE_AGENT_CLAUDE = "1";
        UNSNOOZE_AGENT_CODEX = "1";
      };

      # Keep the Home Manager-owned .zshrc immutable and declare the same wrappers
      # that `unsnooze setup` would otherwise append to it imperatively.
      programs.zsh.initContent = lib.mkAfter ''
        # >>> unsnooze >>>
        case ":$PATH:" in
          *":${config.home.homeDirectory}/.local/bin:"*) ;;
          *) export PATH="${config.home.homeDirectory}/.local/bin:$PATH" ;;
        esac

        claude() {
          if [[ "''${UNSNOOZE_ACTIVE:-}" == "1" ]] || [[ ! -x "${unsnooze}/bin/unsnooze" ]]; then
            command claude "$@"
            return $?
          fi
          "${unsnooze}/bin/unsnooze" _run claude "$@"
        }

        codex() {
          if [[ "''${UNSNOOZE_ACTIVE:-}" == "1" ]] || [[ ! -x "${unsnooze}/bin/unsnooze" ]]; then
            command codex "$@"
            return $?
          fi
          "${unsnooze}/bin/unsnooze" _run codex "$@"
        }
        # <<< unsnooze <<<
      '';

      # Claude's StopFailure hook is the authoritative detection channel. Merge it
      # into the mutable Claude settings file without taking ownership of the rest
      # of that file (status line, permissions, and future user settings survive).
      home.activation.unsnoozeClaudeHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settings=${lib.escapeShellArg "${config.home.homeDirectory}/.claude/settings.json"}
        settings_dir=${lib.escapeShellArg "${config.home.homeDirectory}/.claude"}
        ${pkgs.coreutils}/bin/mkdir -p "$settings_dir"

        if [[ -e "$settings" ]]; then
          if [[ ! -e "$settings.unsnooze-orig" ]]; then
            ${pkgs.coreutils}/bin/cp "$settings" "$settings.unsnooze-orig"
          fi
          ${pkgs.coreutils}/bin/cp "$settings" "$settings.unsnooze-bak"
          source_file="$settings"
        else
          source_file="$(${pkgs.coreutils}/bin/mktemp)"
          printf '{}\n' > "$source_file"
        fi

        tmp="$(${pkgs.coreutils}/bin/mktemp "$settings_dir/.settings.unsnooze.XXXXXX")"
        ${pkgs.jq}/bin/jq \
          --arg command 'test -f "${unsnooze}/lib/node_modules/unsnooze/bin/unsnooze.js" && ${pkgs.nodejs_24}/bin/node "${unsnooze}/lib/node_modules/unsnooze/bin/unsnooze.js" _hook-stopfailure || exit 0' \
          '
            def is_unsnooze_hook:
              any(.hooks[]?;
                ((.command // "") | contains("unsnooze") and contains("_hook-stopfailure"))
              );
            .hooks = (.hooks // {})
            | .hooks.StopFailure = (
                ((.hooks.StopFailure // []) | map(select(is_unsnooze_hook | not)))
                + [{
                    matcher: "overloaded|server_error|rate_limit",
                    hooks: [{ type: "command", command: $command, timeout: 5 }]
                  }]
              )
          ' "$source_file" > "$tmp"
        ${pkgs.coreutils}/bin/chmod 600 "$tmp"
        ${pkgs.coreutils}/bin/mv "$tmp" "$settings"

        if [[ "$source_file" != "$settings" && "$source_file" != "$settings.unsnooze-bak" ]]; then
          ${pkgs.coreutils}/bin/rm -f "$source_file"
        fi
      '';

      # This also watches Claude/Codex GUI session files and owns the singleton
      # resumer. Agent binaries come from the Home Manager profile at runtime.
      systemd.user.services.unsnooze = {
        Unit = {
          Description = "Unsnooze AI coding sessions after usage limits reset";
          StartLimitIntervalSec = 0;
        };

        Service = {
          Type = "simple";
          ExecStart = "${unsnooze}/bin/unsnooze daemon";
          Environment = [
            "PATH=${config.home.profileDirectory}/bin:${daemonPath}"
            "UNSNOOZE_MULTIPLEXER=auto"
            "UNSNOOZE_UPDATE_CHECK=0"
            "UNSNOOZE_AGENT_CLAUDE=1"
            "UNSNOOZE_AGENT_CODEX=1"
            # Prevent Unsnooze's legacy-unit self-healer from mistaking the
            # Home Manager-rendered Environment line for an old unmanaged unit.
            "UNSNOOZE_SYSTEMD_USER_DIR=${config.xdg.configHome}/unsnooze-systemd-managed"
          ];
          Restart = "always";
          RestartSec = 30;
        };

        Install.WantedBy = [ "default.target" ];
      };
    };
}
