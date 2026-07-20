{
  flake.modules.homeManager.iina =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.iina ];
    };
}
