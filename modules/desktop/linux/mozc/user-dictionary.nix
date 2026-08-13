{
  # Declarative mozc user dictionary: entries below are converted to mozc's
  # binary user_dictionary.db at build time and installed on activation,
  # backing up any imperatively edited dictionary first.
  flake.modules.homeManager."desktop/linux" =
    { lib, pkgs, ... }:
    let
      entries = [
        {
          key = "わからない";
          value = "不明点・懸念事項があれば何でも私に質問してください。明確になってからplan modeに入りましょう";
          pos = "品詞なし";
          comment = "";
        }
      ];

      toTsvLine =
        entry:
        lib.concatStringsSep "\t" [
          entry.key
          entry.value
          (entry.pos or "名詞")
          (entry.comment or "")
        ];

      dictionaryTsv = pkgs.writeText "mozc-user-dictionary.tsv" (
        lib.concatStringsSep "\n" (
          [
            "# key\tvalue\tpos\tcomment"
          ]
          ++ map toTsvLine entries
        )
        + "\n"
      );

      dictionaryDb =
        pkgs.runCommand "mozc-user-dictionary-db" { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
            mkdir -p "$out"
            python3 ${./mozc-user-dictionary-to-db.py} ${dictionaryTsv} "$out/user_dictionary.db"
          '';
    in
    lib.mkIf (entries != [ ]) {
      xdg.configFile."mozc/user_dictionary.tsv".source = dictionaryTsv;

      home.activation.installMozcUserDictionary = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        desired_db="${dictionaryDb}/user_dictionary.db"
        dest="$HOME/.config/mozc/user_dictionary.db"
        state_dir="$HOME/.local/state/nix-mozc"
        marker="$state_dir/user_dictionary.db.sha256"

        hash_file() {
          ${pkgs.coreutils}/bin/sha256sum "$1" | ${pkgs.coreutils}/bin/cut -d ' ' -f 1
        }

        desired_hash="$(hash_file "$desired_db")"
        current_hash=""
        if [ -e "$dest" ]; then
          current_hash="$(hash_file "$dest")"
        fi

        if [ "$current_hash" != "$desired_hash" ]; then
          ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/mozc" "$state_dir"
          ${pkgs.procps}/bin/pkill -u "$USER" -x mozc_server 2>/dev/null || true

          previous_hash=""
          if [ -e "$marker" ]; then
            previous_hash="$(${pkgs.coreutils}/bin/cat "$marker")"
          fi

          if [ -n "$current_hash" ] && [ "$current_hash" != "$previous_hash" ]; then
            backup="$dest.backup-$(${pkgs.coreutils}/bin/date +%Y%m%d%H%M%S)"
            ${pkgs.coreutils}/bin/cp -p "$dest" "$backup"
          fi

          ${pkgs.coreutils}/bin/install -m 0600 "$desired_db" "$dest.tmp"
          ${pkgs.coreutils}/bin/mv "$dest.tmp" "$dest"
        fi

        ${pkgs.coreutils}/bin/mkdir -p "$state_dir"
        ${pkgs.coreutils}/bin/printf '%s\n' "$desired_hash" > "$marker"
      '';
    };
}
