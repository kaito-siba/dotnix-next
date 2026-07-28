{ config, ... }:
let
  fonts = config.flake.meta.fonts;
in
{
  # Noctalia v5 (C++ ネイティブ版) — メインのデスクトップシェル。
  # v4 (quickshell 版) の設定に寄せた宣言的設定を config.toml として生成する。
  # settings は build 時に本体のバリデータで検証される (validateConfig)。
  flake.modules = {
    nixos.noctalia = {
      nix.settings = {
        substituters = [ "https://noctalia.cachix.org" ];
        trusted-public-keys = [
          "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
        ];
      };
    };

    homeManager.noctalia =
      { inputs, pkgs, ... }:
      {
        imports = [ inputs.noctalia.homeModules.default ];

        home.packages = with pkgs; [
          gpu-screen-recorder # screen_recorder 公式プラグインの依存
          translate-shell # translator 公式プラグインの依存
          wtype # launcher の auto-paste 用
          gradia # スクリーンショット注釈
        ];

        programs.noctalia = {
          enable = true;

          # niri セッション (graphical-session.target) に載せて常駐させる
          systemd.enable = true;

          settings = {
            shell = {
              font_family = fonts.ui;
              avatar_path = "~/.config/noctalia/avatar.jpg";
              telemetry_enabled = false;
            };

            # colorscheme は一旦 catppuccin。mode = auto は location から
            # 昼夜で light/dark を切り替える (ghostty 等の auto 切替と整合)。
            # アプリテーマ生成 (templates) は無効化し、各アプリは共有モジュール
            # の静的 catppuccin を使い続ける。
            theme = {
              source = "builtin";
              builtin = "Catppuccin";
              mode = "auto";
              templates = {
                enable_builtin_templates = false;
                enable_community_templates = false;
              };
            };

            location = {
              address = "Kobe";
            };

            wallpaper = {
              enabled = true;
              directory = "~/Pictures/wallpapers";
            };

            # v4 のバー構成に寄せる: 左 control-center / 中央 workspace+media /
            # 右 システム系 + 時計 + 通知。vibe-island は自作プラグインの島。
            bar = [
              {
                position = "top";
                background_opacity = 0.8;
                margin_edge = 7;
                margin_ends = 7;
                start_widgets = [ "control-center" ];
                center_widgets = [
                  "workspaces"
                  "media"
                ];
                end_widgets = [
                  "kaito/vibe-island:island"
                  "tray"
                  "network"
                  "bluetooth"
                  "volume"
                  "clock"
                  "notifications"
                ];
              }
            ];

            # v5 には v4 の syncGsettings に相当する仕組みが無いため、テーマの
            # light/dark を hook で gsettings (portal 経由で各アプリが追従) に
            # 反映する。started はログイン直後の初期同期用。
            hooks = {
              theme_mode_changed = [ "~/.local/bin/set-gnome-color-schema" ];
              started = [ "~/.local/bin/set-gnome-color-schema" ];
            };

            # ローカルの自作プラグイン (~/.local/share/noctalia/plugins/ に配置)
            # と公式プラグインを宣言的に有効化する。
            plugins = {
              enabled = [
                "kaito/custom-commands"
                "kaito/vibe-island"
                "noctalia/screen_recorder"
                "noctalia/translator"
              ];
            };
          };
        };

        # ダークモード切替時に GNOME の color-scheme を追従させるフックスクリプト
        home.file.".local/bin/set-gnome-color-schema" = {
          source = ./scripts/set-gnome-color-schema;
          executable = true;
        };

        # 自作ローカルプラグイン
        xdg.dataFile."noctalia/plugins/custom-commands".source = ./plugins/custom-commands;
        xdg.dataFile."noctalia/plugins/vibe-island".source = ./plugins/vibe-island;

        # アバターは repo の assets から供給する (壁紙は ~/Pictures/wallpapers の
        # 実ディレクトリを直接参照し、repo には同梱しない)
        xdg.configFile."noctalia/avatar.jpg".source = ../../assets/icons/icon_1.jpg;

        # niri の config.kdl が include する外観オーバーライド。v4 ではテンプレート
        # 生成だったが、catppuccin 統一に伴い静的ファイル (mocha アクセント) にする。
        xdg.configFile."niri/noctalia-transparent.kdl".source = ./niri-appearance.kdl;
      };
  };
}
