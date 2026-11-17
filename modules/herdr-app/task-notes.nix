{
  # herdr の tab ごとに、そこで動く Claude Code が何をしているかの要約を書く
  # (./task-notes/task-notes.py)。herdr-app の tasks mod がそれを出す。
  # Claude Code の Stop hook から呼ばれる。最初の要約はファイルを書き換えた
  # turn の後に作り、要約のある tab では turn のたびに、裏で Haiku を 1 回
  # 走らせる (subscription の枠を使う)。herdr の端末の外では何もしない。agent の
  # 動く machine に要るので、herdr-app を入れる全ての machine に入れる。
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
    in
    {
      home.packages = [ task-notes ];

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
