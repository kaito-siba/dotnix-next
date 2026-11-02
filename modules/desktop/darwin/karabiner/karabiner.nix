{
  # Karabiner-Elements is installed by hand from https://karabiner-elements.pqrs.org/
  # and updates itself: it ships a system extension and a virtual HID driver,
  # updates frequently, and pinning it in the Brewfile only meant falling
  # behind. Nix contributes the configuration.
  #
  # Only karabiner.json is vendored: assets/ and automatic_backups/ next to
  # it are written by the app and must stay writable. The GUI saves settings
  # by replacing karabiner.json, which clobbers the symlink -- the next
  # switch backs that up as .before-nix and restores the repo version, so
  # changes flow through this file, not the GUI.
  flake.modules.homeManager."desktop/darwin" =
    { pkgs, lib, ... }:
    lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      xdg.configFile."karabiner/karabiner.json".source = ./config/karabiner.json;
    };
}
