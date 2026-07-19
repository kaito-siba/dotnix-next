{
  nixpkgs.allowedUnfreePackages = [ "obsidian" ];

  flake.modules.homeManager.obsidian =
    { pkgs, ... }:
    {
      programs.obsidian = {
        enable = true;
        cli.enable = true;
      };
    };
}
