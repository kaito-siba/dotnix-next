{
  nixpkgs.allowedUnfreePackages = [ "intelephense" ];

  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        intelephense
      ];
    };
}
