{
  flake.modules.homeManager.scroll-reverser =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.scroll-reverser ];
    };
}
