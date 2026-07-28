{
  nixpkgs.allowedUnfreePackages = [ "vscode" ];

  flake.modules.homeManager.vscode =
    { pkgs-unstable, ... }:
    {
      programs.vscode = {
        enable = true;
        package = pkgs-unstable.vscode;
      };
    };
}
