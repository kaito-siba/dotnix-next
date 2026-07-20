{
  nixpkgs.allowedUnfreePackages = [ "appcleaner" ];

  flake.modules.homeManager.appcleaner =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.appcleaner ];
    };
}
