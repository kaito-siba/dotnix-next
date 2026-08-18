{
  nixpkgs.allowedUnfreePackages = [ "shottr" ];

  flake.modules.homeManager."desktop/darwin" =
    { pkgs, lib, ... }:
    lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      home.packages = [ pkgs.shottr ];
    };
}
