{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  # Apps this host needs but nix deliberately does not manage:
  # Microsoft Teams and TeamViewer come from the vendors' .pkg installers,
  # which keeps them out of homebrew's declarative cleanup.
  flake.modules.darwin."hosts/incarnata" = {
    imports =
      with config.flake.modules.darwin;
      [
        base
        homebrew
        desktop
        fonts
        tailscale
        activitywatch

        # Development
        dev

        # Users
        k-nanchi
      ]
      ++ [
        {
          home-manager.users.k-nanchi.imports = [
            hm.base
            hm."desktop/darwin"
            hm.shell
            hm.neovim
            hm.obsidian
            hm.ghostty

            # Desktop applications
            hm.appcleaner
            hm.video-player
            hm.smoothcsv
            hm.vesktop
            hm.slack

            # Development
            hm.dev
            hm.ai

            # Time tracking
            hm.activitywatch
          ];
        }
      ];
  };
}
