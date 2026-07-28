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
        wl-mirror # screen mirroring (noctalia custom command)
      ];

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
