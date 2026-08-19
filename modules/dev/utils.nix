{
  # Language-agnostic development utilities.
  flake.modules.homeManager.dev =
    {
      pkgs,
      pkgs-unstable,
      ...
    }:
    {
      home.packages =
        (with pkgs; [
          git-filter-repo # history rewriting for repo surgery
        ])
        ++ (with pkgs-unstable; [
          devenv # reproducible per-project dev environments
          keifu # git commit graph TUI
          mise # some projects use it as their task runner
        ]);
    };
}
