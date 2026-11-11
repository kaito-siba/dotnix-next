{
  # Herdr の desktop app (herdrdev/herdr-app) と、その端末を動かす herdr-core。
  # shell モジュールの herdr (TUI, herdrdev/herdr) とは別物で、コマンド名
  # (herdr-app / herdr-core / hc) も設定の置き場 (~/.config/herdr-app,
  # ~/.config/herdr-core) も重ならないので併存できる。
  flake.modules.homeManager.herdr-app =
    { pkgs, lib, ... }:
    let
      herdr-core = pkgs.callPackage ./_core.nix { };

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

        "shift-s" = "app.settings";
        "b" = "layout.toggle:sidebar";
        "?" = "app.help";
      }
      // lib.genAttrs (map toString (lib.range 1 9)) (n: "tab.select:${n}");
    in
    {
      home.packages = [
        herdr-core
        (pkgs.callPackage ./_package.nix { inherit herdr-core; })
      ];

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
