{
  # GNOME mail client: the Linux incumbent while aerion is on trial.
  flake.modules.homeManager.mail =
    { pkgs, lib, ... }:
    lib.mkIf pkgs.stdenv.isLinux {
      home.packages = [ pkgs.geary ];
    };
}
