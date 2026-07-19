{ config, ... }:
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
          home-manager.users.root.imports = with config.flake.modules.homeManager; [
            base
            shell
            neovim
          ];
        }
      ];
  };
}
