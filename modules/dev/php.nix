{
  nixpkgs.allowedUnfreePackages = [ "intelephense" ];

  flake.modules.homeManager."dev/php" =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        intelephense
      ];
    };
}
