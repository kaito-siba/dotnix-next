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
          bitwarden-cli # bitwarden 公式プラグインの依存 (プラグインが bw serve を自前で起動する)
          hyprpicker # color_picker コミュニティプラグインの依存
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

              external_ip_enabled = true;
              niri_overview_type_to_launch_enabled = true;
              password_style = "random";
              polkit_agent = true;
              screen_time_enabled = true;

              # クリップボードの画像とスクリーンショットはどちらも gradia に流す
              clipboard_image_action_command = "gradia";
              screenshot = {
                directory = "~/Pictures/Screenshots";
                pipe_to_command = true;
                pipe_command = "gradia";
              };

              launcher = {
                categories = false;
                compact = true;
                providers.emoji.prefix = "em";
              };

              panel.open_near_click_control_center = true;
            };

            notification.history_retention_hours = 48;

            calendar = {
              enabled = true;
              account.personal_google = {
                name = "Private";
                type = "google";
              };
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

            # 実際に選ばれている壁紙 (wallpaper.default / .last / .monitors.*) は
            # automation で入れ替わるランタイム状態なので state 側に任せる。
            wallpaper = {
              enabled = true;
              directory = "~/Pictures/wallpapers";
              automation.enabled = true;
            };

            # 左 control-center / 中央 workspaces+media / 右 システム系 + 時計 +
            # 通知。vibe-island は自作プラグインの島。
            #
            # v5 のバーは [bar.<名前>] の名前付きテーブルで、ウィジェット一覧の
            # キーは start / center / end。v4 の [[bar]] + *_widgets 形式で書くと
            # config validate は素通りするのに実行時に黙って捨てられる。
            bar.main = {
              position = "top";
              thickness = 24;
              background_opacity = 0.85;
              margin_edge = 6;
              margin_ends = 12;

              start = [ "control-center" ];
              center = [
                "media"
              ];
              end = [
                "kaito/vibe-island:island"
                "cpu"
                "ram"
                "network"
                "bluetooth"
                "volume"
                "clock"
                "notifications"
              ];
            };

            # バーに載せるウィジェット個別の設定
            widget = {
              clock.format = "{:%Y/%m/%d %H:%M}";
              control-center = {
                color = "primary";
                glyph = "brand-snowflake";
              };
              # システムモニタ系はアイコンのみ (ラベルを出すと横幅を食う)
              cpu.show_label = false;
              ram.show_label = false;
              network.show_label = false;
            };

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
                "noctalia/bitwarden"
                "oldirtty/color_picker"
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

      };
  };
}
