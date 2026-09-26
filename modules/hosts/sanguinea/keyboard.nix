{
  # Modmap for the built-in keyboard.
  flake.modules.nixos."hosts/sanguinea" = {
    services.xremap.config.modmap = [
      {
        name = "Global";
        remap = {
          "CapsLock" = "Ctrl_L";
          "Ctrl_L" = "CapsLock";
          "Super_L" = "Alt_L";

          # You need to set the action of 'Muhenkan' to 'Deactivate IME' from the mozc settings and remove all Shift + 'Muhenkan' entries.
          # mozc settings location: fcitx-configtool -> Addons -> Mozc -> Configuration Tool -> Keymap Style
          "Alt_L" = {
            held = "Super_L";
            alone = "Muhenkan";
            alone_timeout_mills = 200;
          };
          "Alt_R" = {
            held = "Alt_R";
            alone = "Hiragana";
            alone_timeout_mills = 200;
          };
        };
      }
    ];
  };
}
