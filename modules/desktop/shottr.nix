{
  nixpkgs.allowedUnfreePackages = [ "shottr" ];

  flake.modules.homeManager.desktop =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.shottr ];
    };
}
