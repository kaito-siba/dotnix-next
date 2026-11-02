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
          mise # some team projects use it as their task runner
        ])
        ++ (with pkgs-unstable; [
          # One of the few packages allowed from unstable (see flake.nix):
          # stable ships 0.3 against upstream's 0.7.
          keifu # git commit graph TUI
        ]);
    };
}
