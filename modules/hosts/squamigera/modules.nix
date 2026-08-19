{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.darwin."hosts/squamigera" = {
    imports =
      with config.flake.modules.darwin;
      [
        base
        homebrew
        desktop
        fonts
        photography
        tailscale

        # Development
        dev

        # Users
        w963n
      ]
      ++ [
        {
          home-manager.users.w963n.imports = [
            hm.base
            hm."desktop/darwin"
            hm.shell
            hm.neovim
            hm.obsidian
            hm.ghostty

            # Desktop applications
            hm.appcleaner
            hm.video-player
            hm.mail
            hm.smoothcsv

            # Development
            hm.dev
          ];
        }
      ];
  };
}
