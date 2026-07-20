{
  # mkIf isDarwin, here and in the sibling files: these are mac-only apps, and
  # the homeManager class is shared across platforms. Without the guard a
  # NixOS host importing desktop would fail evaluation on them.
  flake.modules.homeManager.desktop =
    { pkgs, lib, ... }:
    lib.mkIf pkgs.stdenv.isDarwin {
      home.packages = [ pkgs.hidden-bar ];
    };
}
