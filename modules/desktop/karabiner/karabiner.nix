{
  flake.modules = {
    # Ships a system extension, so it stays a cask.
    darwin.desktop = {
      homebrew.casks = [ "karabiner-elements" ];
    };

    # Only karabiner.json is vendored: assets/ and automatic_backups/ next to
    # it are written by the app and must stay writable. The GUI saves settings
    # by replacing karabiner.json, which clobbers the symlink -- the next
    # switch backs that up as .before-nix and restores the repo version, so
    # changes flow through this file, not the GUI.
    homeManager.desktop =
      { pkgs, lib, ... }:
      lib.mkIf pkgs.stdenv.isDarwin {
        xdg.configFile."karabiner/karabiner.json".source = ./config/karabiner.json;
      };
  };
}
