{
  # Session-wide wayland plumbing for the Linux desktop: toolkit backends,
  # portals, clipboard CLI and the pointer cursor.
  #
  # The hyprland configuration that used to live next to this was dropped:
  # the session runs niri, and hyprlock / hyprpaper / hyprpanel duties are
  # covered by noctalia.
  flake.modules.homeManager."desktop/linux" =
    { pkgs, config, ... }:
    {
      home.packages = with pkgs; [
        wl-clipboard
        wl-clip-persist
        wl-mirror # screen mirroring (noctalia custom command)
      ];

      # Wayland のクリップボードは「内容を持っているプロセスが生きている」
      # 前提で動くため、nvim の yank が起動する wl-copy が死ぬと中身ごと
      # 消えて GUI 側の paste が空になる。ssh (herdr --remote) 経由で
      # yank したあとセッションが切れるとこれを踏む。wl-clip-persist に
      # 内容を引き取らせて、所有者が消えてもクリップボードを残す。
      systemd.user.services.wl-clip-persist = {
        Unit = {
          Description = "Keep the Wayland clipboard after the owning program exits";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };

        Service = {
          Type = "simple";
          # regular のみ: primary (選択即コピー) まで保持すると
          # 選択のたびに履歴が汚れる。
          # 32MiB 超は保持しない (画像・動画コピーで常駐 RAM が膨らむのを防ぐ)。
          ExecStart = toString [
            "${pkgs.wl-clip-persist}/bin/wl-clip-persist"
            "--clipboard regular"
            "--ignore-event-on-error"
            "--selection-size-limit 33554432"
            "--reconnect-tries inf"
            "--disable-timestamps"
          ];
          Restart = "on-failure";
          RestartSec = 5;
        };

        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };

      home.pointerCursor = {
        gtk.enable = true;
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Ice";
        size = 8;
      };

      xdg.configFile."electron-flags.conf".text = ''
        --enable-features=UseOzonePlatform
        --ozone-platform=wayland
      '';

      xdg.configFile."code-flags.conf".source =
        config.xdg.configFile."electron-flags.conf".source;
      xdg.configFile."spotify-flags.conf".source =
        config.xdg.configFile."electron-flags.conf".source;

      xdg.configFile."xdg-desktop-portal/portals.conf".text = ''
        [preferred]
        default=gnome;gtk;
        org.freedesktop.impl.portal.FileChooser=gtk
        org.freedesktop.impl.portal.ScreenCast=gnome
        org.freedesktop.impl.portal.RemoteDesktop=gnome
      '';

      home.sessionVariables = {
        NIXOS_OZONE_WL = "1"; # Electron apps to use Wayland
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
        # Xwayland clients use XIM for IME integration.
        XMODIFIERS = "@im=fcitx";
        QT_QPA_PLATFORM = "wayland";
        QT_QPA_PLATFORMTHEME = "qt6ct";
        SDL_VIDEODRIVER = "wayland";
      };
    };
}
