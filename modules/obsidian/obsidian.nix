{
  nixpkgs.allowedUnfreePackages = [ "obsidian" ];

  # The binary comes from nixpkgs on every platform. Managing it as a cask
  # instead would collide with this module's design: it writes obsidian.json
  # with the app's self-updater disabled, which only makes sense when nix owns
  # the package.
  flake.modules.homeManager.obsidian = {
    programs.obsidian = {
      enable = true;
      cli.enable = true;
    };
  };
}
