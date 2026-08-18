{ config, ... }:
{
  # GTK/Qt appearance on the Linux desktop.
  flake.modules.homeManager."desktop/linux" =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        adw-gtk3
        qt6Packages.qt6ct
        libsForQt5.qt5ct
      ];

      gtk = {
        enable = true;
        theme = {
          name = "adw-gtk3";
          package = pkgs.adw-gtk3;
        };
        # adw-gtk3 ships no gtk-4.0 theme, so pointing GTK4 at it (the pre-26.05
        # legacy default) was a no-op; null lets GTK4/libadwaita use its default.
        gtk4.theme = null;
        iconTheme = {
          package = pkgs.qogir-icon-theme;
          name = "Qogir";
        };
        font = {
          name = config.flake.meta.fonts.ui;
        };
      };

      # https://discourse.nixos.org/t/changing-gdm-gsettings-declaratively/49579/7
      dconf.settings = {
        "org/gnome/desktop/interface" = {
          gtk-theme = "adw-gtk3";
        };
      };
    };
}
