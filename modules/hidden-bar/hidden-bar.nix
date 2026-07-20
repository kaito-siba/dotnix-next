{
  flake.modules.homeManager.hidden-bar =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.hidden-bar ];
    };
}
