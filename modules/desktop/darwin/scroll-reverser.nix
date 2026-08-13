{
  flake.modules.homeManager."desktop/darwin" =
    { pkgs, lib, ... }:
    lib.mkIf pkgs.stdenv.isDarwin {
      home.packages = [ pkgs.scroll-reverser ];
    };
}
