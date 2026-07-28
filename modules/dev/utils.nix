{
  # Language-agnostic development utilities.
  flake.modules.homeManager.dev =
    { pkgs-unstable, ... }:
    {
      home.packages = with pkgs-unstable; [
        devenv # reproducible per-project dev environments
        keifu # git commit graph TUI
      ];
    };
}
