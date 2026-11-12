{ config, ... }:
let
  fonts = config.flake.meta.fonts;
in
{
  # Herdr の desktop app (herdrdev/herdr-app) と、その端末を動かす herdr-core。
  # shell モジュールの herdr (TUI, herdrdev/herdr) とは別物で、コマンド名
  # (herdr-app / herdr-core / hc) も設定の置き場 (~/.config/herdr-app,
  # ~/.config/herdr-core) も重ならないので併存できる。
  flake.modules.homeManager.herdr-app =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      herdr-core = pkgs.callPackage ./_core.nix { };
      herdr-app = pkgs.callPackage ./_package.nix { inherit herdr-core; };

      # Show: セッションの横に、エージェントが `show <file>` で送ってきた物
      # (主にスクリーンショット) を並べる右パネル。開いて注釈を描き、その
      # コピーを保存したり prompt に貼り戻したりできる。中身は ./show、
      # 組み立ては ./_show.nix。Show を足した layout (lycoreco) もここで作る。
      # Agents の一覧の下には絵を敷ける: 画像は repo に入れず、
      # ~/.config/herdr-app/backgrounds/sidebar.png に置く (./backdrop)。
      show = pkgs.callPackage ./_show.nix { appVersion = herdr-app.version; };

      # settings.json のうち nix で決める項目。theme は ./themes の名前で、
      # layout が自分の theme を持たない所で使われる。
      settings = {
        theme = {
          light = "lycoreco-chisato";
          dark = "lycoreco-takina";
        };
        font = fonts.coding;
        ui_font = fonts.ui;
      };

      # keys.json は app の既定値を丸ごと置き換えるので、同梱の既定値
      # (defaults/keys.json の写し。app を bump したら写し直す) に足す形で作る。
      defaults = lib.importJSON ./keys.default.json;

      # TUI 版 (modules/shell/herdr/config.toml) と同じ prefix。keys.json の
      # キーは空白区切りで sequence になる (herdrdev/herdr-app#833)。
      prefix = "ctrl-space";

      # TUI 版の既定値と config.toml の上書きを合わせた割り当てを、app の
      # コマンドに読み替えたもの。app に相当するコマンドが無いものは移せない:
      # last_pane (;), cycle_pane (o / tab / shift-tab), resize_mode (r,
      # herdrdev/herdr-app#117), open_notification_target (shift-o),
      # new_worktree (shift-g), copy_mode ([)。
      prefixed = {
        # window を閉じても端末は core で動き続けるので、detach に当たる。
        "d" = "window.close";

        "c" = "tab.new";
        "," = "tab.rename";
        "shift-x" = "tab.close";
        "p" = "tab.prev";
        "n" = "tab.next";

        # herdrdev/herdr/discussions/1457
        "ctrl-x" = "pane.close";
        "z" = "pane.zoom";
        "|" = "pane.split:right";
        "\\" = "pane.split:right";
        "-" = "pane.split:down";
        "_" = "pane.split:down";
        "h" = "pane.go:left";
        "j" = "pane.go:down";
        "k" = "pane.go:up";
        "l" = "pane.go:right";
        "shift-h" = "pane.swap:left";
        "shift-j" = "pane.swap:down";
        "shift-k" = "pane.swap:up";
        "shift-l" = "pane.swap:right";

        "shift-n" = "space.new";
        "shift-d" = "space.close";
        "$" = "space.rename";
        "shift-w" = "space.rename";

        # workspace_picker と goto はどちらも picker (tab / space / agent を
        # 絞り込んで移動) に寄せる。
        "w" = "mod.open:picker";
        "s" = "mod.open:picker";

        # 自作の mod (./mods)。もう一度押すと閉じる。g は git まわりで、
        # nvim の <leader>g に合わせている。
        "shift-p" = "mod.open:scratchpad";
        "g g" = "mod.open:lazygit";
        "g p" = "mod.open:pr";

        "shift-s" = "app.settings";
        "b" = "layout.toggle:sidebar";
        "?" = "app.help";
      }
      // lib.genAttrs (map toString (lib.range 1 9)) (n: "tab.select:${n}");
    in
    {
      home.packages = [
        herdr-core
        herdr-app
        show.show
      ];

      # mod と layout は symlink では置けない: app は mod の asset を app home
      # の外へ辿らずに読み (gpui-kit の AppAssets)、layout には自分でも書く。
      # なので実体をコピーする。中身が同じなら触らない (書くたびに mod が
      # reload される)。入れた後は一度 layout を切り替える:
      #   herdr-app do layout.switch --name lycoreco
      home.activation.installHerdrAppShow = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        app_home="${config.xdg.configHome}/herdr-app"
        (
          cd ${show}
          ${pkgs.findutils}/bin/find . -type f -print0 | while IFS= read -r -d "" file; do
            if ! ${pkgs.diffutils}/bin/cmp -s "$file" "$app_home/$file"; then
              run ${pkgs.coreutils}/bin/install -Dm644 "$file" "$app_home/$file"
            fi
          done
        )
      '';

      # app は mod を読む時に、その folder へ jsconfig.json と gpui-kit.d.ts を
      # 書き出す。folder ごと store への link にすると書けないので、recursive で
      # ファイル単位の link にする。
      xdg.configFile."herdr-app/mods/scratchpad" = {
        source = ./mods/scratchpad;
        recursive = true;
      };
      xdg.configFile."herdr-app/mods/pr" = {
        source = ./mods/pr;
        recursive = true;
      };
      xdg.configFile."herdr-app/mods/lazygit" = {
        source = ./mods/lazygit;
        recursive = true;
      };

      # リコリス・リコイルの千束 (light) とたきな (dark) の theme。差し色と
      # 状態の色は公式サイトの各キャラの色: 千束 #f0555a、たきな #2a96fa、
      # ミズキ #00b4aa、クルミ #ffe76c、ミカ #7a5668。端末の文字になる色は、
      # 地の上で読めるように濃さを変えてある。
      xdg.configFile."herdr-app/themes/lycoreco-chisato.json".source = ./themes/lycoreco-chisato.json;
      xdg.configFile."herdr-app/themes/lycoreco-takina.json".source = ./themes/lycoreco-takina.json;

      # settings.json は app も書く (zoom、音、Settings での変更) ので、
      # 丸ごとは置けない。nix で決める項目だけを上書きして、他は残す。
      # 中身が変わらない時は触らない (書くたびに app が読み直す)。
      # Settings の theme picker で選んだ物は layout の側に残り、ここより
      # 優先される。
      home.activation.setHerdrAppSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settings="${config.xdg.configHome}/herdr-app/settings.json"
        current='{}'
        if [ -e "$settings" ]; then
          current=$(${pkgs.coreutils}/bin/cat "$settings")
        fi
        if merged=$(${pkgs.jq}/bin/jq --argjson declared ${lib.escapeShellArg (builtins.toJSON settings)} '. + $declared' <<<"$current"); then
          if [ "$merged" != "$(${pkgs.jq}/bin/jq . <<<"$current")" ]; then
            run ${pkgs.coreutils}/bin/install -Dm644 /dev/stdin "$settings" <<<"$merged"
          fi
        else
          echo "herdr-app: $settings を JSON として読めないので、theme と font を書き込まなかった" >&2
        fi
      '';

      xdg.configFile."herdr-app/keys.json".text = builtins.toJSON (
        defaults
        // {
          global =
            defaults.global
            // lib.mapAttrs' (key: action: lib.nameValuePair "${prefix} ${key}" action) prefixed;
        }
      );
    };
}
