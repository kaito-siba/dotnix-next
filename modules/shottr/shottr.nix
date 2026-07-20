{
  nixpkgs.allowedUnfreePackages = [ "shottr" ];

  flake.modules.homeManager.shottr =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.shottr ];
    };
}
