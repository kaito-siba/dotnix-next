{
  # GTK/Qt appearance on the Linux desktop. noctalia.css referenced from the
  # gtk4 import is generated at runtime by noctalia.
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
        iconTheme = {
          package = pkgs.qogir-icon-theme;
          name = "Qogir";
        };
        font = {
          name = "Noto Sans CJK JP";
        };
        gtk4.extraCss = ''
          @import url("noctalia.css");
        '';
      };

      # https://discourse.nixos.org/t/changing-gdm-gsettings-declaratively/49579/7
      dconf.settings = {
        "org/gnome/desktop/interface" = {
          gtk-theme = "adw-gtk3";
        };
      };
    };
}
