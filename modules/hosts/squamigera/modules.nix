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
        hammerspoon
        fonts

        # Users
        w963n
      ]
      ++ [
        {
          home-manager.users.w963n.imports = [
            hm.base
            hm.shell
            hm.neovim
            hm.gnupg
            hm.lazysql
            hm.obsidian
            hm.ghostty

            # Desktop applications
            hm.appcleaner
            hm.hidden-bar
            hm.iina
            hm.scroll-reverser
            hm.shottr

            # Development
            hm."dev/common"
            hm."dev/nix"
            hm."dev/rust"
            hm."dev/web"
            hm."dev/python"
          ];
        }
      ];
  };
}
