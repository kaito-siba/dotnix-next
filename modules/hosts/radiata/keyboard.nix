{
  # Modmap for the Nuphy Air75 attached to this host.
  flake.modules.nixos."hosts/radiata" = {
    services.xremap.config.modmap = [
      {
        name = "Nuphy";
        device = {
          only = [ "BY Tech Air75" ];
        };
        remap = {
          "CapsLock" = "Ctrl_L";
          "Ctrl_L" = "CapsLock";

          # You need to set the action of 'Muhenkan' to 'Deactivate IME' from the mozc settings and remove all Shift + 'Muhenkan' entries.
          # mozc settings location: fcitx-configtool -> Addons -> Mozc -> Configuration Tool -> Keymap Style
          "Super_L" = {
            held = "Super_L";
            alone = "Muhenkan";
            alone_timeout_mills = 200;
          };
          "Super_R" = {
            held = "Super_R";
            alone = "Hiragana";
            alone_timeout_mills = 200;
          };
        };
      }
    ];
  };
}
