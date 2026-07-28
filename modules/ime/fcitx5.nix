{
  flake.modules.nixos.ime =
    { pkgs, ... }:
    {
      i18n.inputMethod = {
        enable = true;
        type = "fcitx5";
        fcitx5.addons = with pkgs; [
          fcitx5-gtk
          fcitx5-mozc-ut
        ];
        fcitx5.waylandFrontend = true;

        fcitx5.settings.inputMethod = {
          GroupOrder."0" = "Default";
          "Groups/0" = {
            Name = "Default";
            "Default Layout" = "us";
            DefaultIM = "mozc";
          };
          "Groups/0/Items/0".Name = "mozc";
        };

        fcitx5.settings.addons = {
          mozc.globalSection.InitialMode = "Direct";
        };
      };
    };
}
