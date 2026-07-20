{
  flake.modules.homeManager.desktop =
    { pkgs, lib, ... }:
    lib.mkIf pkgs.stdenv.isDarwin {
      home.packages = [ pkgs.scroll-reverser ];
    };
}
