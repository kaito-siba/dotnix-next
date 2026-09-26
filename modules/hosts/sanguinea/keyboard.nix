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
            alone_timeout_millis = 200;
          };
          "Alt_R" = {
            held = "Super_R";
            alone = "Hiragana";
            alone_timeout_millis = 200;
          };

          # The Copilot key sends Super_L + Shift_L + F23, and Super_L is already remapped to Alt_L above.
          # Drop F23 and release Shift_L so that only Alt_L stays held.
          "F23" = {
            skip_key_event = true;
            press = [ { release = "Shift_L"; } ];
          };
        };
      }
    ];
  };
}
