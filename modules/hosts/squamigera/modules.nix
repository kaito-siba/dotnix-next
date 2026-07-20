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

        # Users
        w963n
      ]
      ++ [
        {
          home-manager.users.w963n.imports = [
            hm.base
            hm.desktop
            hm.shell
            hm.neovim
            hm.lazysql
            hm.obsidian
            hm.ghostty

            # Desktop applications
            hm.appcleaner
            hm.iina

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
