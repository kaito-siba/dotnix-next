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
