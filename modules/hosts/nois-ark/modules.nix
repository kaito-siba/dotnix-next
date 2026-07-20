{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos."hosts/nois-ark" = {
    imports =
      with config.flake.modules.nixos;
      [
        base
        openssh
        virtualisation
        tailscale
        searxng

        # Users
        root
        noi
      ]
      ++ [
        {
          home-manager.users.root.imports = [
            hm.base
            hm.shell
            hm.neovim

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
