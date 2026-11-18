{
  # herdr の端末で動く Claude Code の session ごとに、何をしているかの記録を書く
  # (./task-notes/task-notes.py)。herdr-app の tasks mod がそれを出す。
  # Claude Code の Stop hook から呼ばれ、turn のたびに裏で Haiku を 1 回走らせる
  # (subscription の枠を使う)。herdr の端末の外では何もしない。agent の
  # 動く machine に要るので、herdr-app を入れる全ての machine に入れる。
  # sbx の sandbox の中の Claude Code は Stop hook を持たないので、host の service
  # (task-notes watch) が端末の状態から turn の終わりを見つける。herdr-app の mod は
  # agent の居る folder を task-notes where で訊く。
  flake.modules.homeManager.herdr-app =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      task-notes = pkgs.writeShellApplication {
        name = "task-notes";
        # claude と hc は PATH の物を使う: どちらも Claude Code の動く環境にある。
        text = ''
          exec ${pkgs.python3}/bin/python3 ${./task-notes/task-notes.py} "$@"
        '';
      };
      hook = {
        hooks = [
          {
            type = "command";
            command = "${lib.getExe task-notes} hook";
            timeout = 10;
          }
        ];
      };

      # Claude Code が約束していない物 (画面の字、transcript の形、hook に渡す key、
      # 一時 folder の置き方) に頼っている所と、その頼りにしている字。Claude Code を
      # 上げて、これらの字が binary から消えたら build を落とす (同梱の layout と mod
      # の写しを ./_app-home.nix で確かめるのと同じ)。字が残ったまま使い方が変わった
      # 時は、task-notes の .error と tasks mod が実行中に出す。sbx の sandbox の中の
      # Claude Code は nix の外で上がるので、ここでは確かめられない。
      claudeCodeMarks = {
        "task-notes/task-notes.py" = [
          # transcript の entry と、session の名前の entry (TITLES)
          "isMeta"
          "isCompactSummary"
          "ai-title"
          "aiTitle"
          "custom-title"
          "customTitle"
          # user の entry に Claude Code が足す物 (INSERTED)
          "<system-reminder>"
          "<local-command"
          "[Request interrupted"
          "Caveat:"
          # Stop hook に渡る key
          "transcript_path"
          "last_assistant_message"
          # 要約に使う claude -p
          "json-schema"
          "structured_output"
          "no-session-persistence"
          "max-budget-usd"
        ];
        # 選ぶ画面の操作の案内 (CHROME)
        "mods/inbox/asks.js" = [
          "Enter to select"
          "to navigate"
          "Esc to cancel"
          "Type something"
          "Chat about this"
        ];
        "mods/scratchpad/main.js" = [
          "CLAUDE_CODE_TMPDIR"
          "scratchpad"
        ];
      };
      claudeCode = config.programs.claude-code.package;
      claudeCodeCheck = pkgs.runCommand "task-notes-claude-code-check" { } ''
        missing=0
        while IFS=$'\t' read -r file mark; do
          grep -rqaF -- "$mark" ${claudeCode}/bin \
            || { echo "Claude Code ${claudeCode.version} に '$mark' が無い: ./modules/herdr-app/$file を合わせる" >&2; missing=1; }
        done < ${
          pkgs.writeText "claude-code-marks" (
            lib.concatStrings (
              lib.mapAttrsToList (file: marks: lib.concatMapStrings (mark: "${file}\t${mark}\n") marks) claudeCodeMarks
            )
          )
        }
        [ "$missing" = 0 ] || exit 1
        touch $out
      '';
    in
    {
      home.packages = [ task-notes ];

      # Claude Code を nix で入れていない machine では確かめない。
      home.extraDependencies = lib.optional (
        config.programs.claude-code.enable && claudeCode != null
      ) claudeCodeCheck;

      # hc events は core が再起動すると切れるので、落ちたら起こし直す。
      systemd.user.services.task-notes = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        Unit.Description = "Summarize Claude Code turns in sbx sandboxes for herdr-app";
        Service = {
          ExecStart = "${lib.getExe task-notes} watch";
          # hc / claude / sbx / git は user の profile、ps は system の物を使う。
          Environment = [
            "PATH=${config.home.profileDirectory}/bin:/run/wrappers/bin:/run/current-system/sw/bin"
          ];
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };

      # ~/.claude/settings.json は Claude Code も他の tool (herdr、unsnooze) も
      # 書くので、丸ごとは置けない。Stop hook に自分の分だけを足す。store の
      # path が変わるので、前に足した分は消してから足し直す。中身が変わらない
      # 時は触らない。
      home.activation.setTaskNotesHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settings="${config.home.homeDirectory}/.claude/settings.json"
        current='{}'
        if [ -e "$settings" ]; then
          current=$(${pkgs.coreutils}/bin/cat "$settings")
        fi
        if merged=$(${pkgs.jq}/bin/jq --argjson hook ${lib.escapeShellArg (builtins.toJSON hook)} '
          .hooks.Stop = ((.hooks.Stop // [])
            | map(select((.hooks // []) | all((.command // "") | test("/bin/task-notes hook$") | not)))
            | . + [$hook])
        ' <<<"$current"); then
          if [ "$merged" != "$(${pkgs.jq}/bin/jq . <<<"$current")" ]; then
            tmp=$(${pkgs.coreutils}/bin/mktemp)
            printf '%s\n' "$merged" >"$tmp"
            run ${pkgs.coreutils}/bin/install -Dm600 "$tmp" "$settings"
            ${pkgs.coreutils}/bin/rm -f "$tmp"
          fi
        else
          echo "task-notes: $settings を JSON として読めないので、Stop hook を足さなかった" >&2
        fi
      '';
    };
}
