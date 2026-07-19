{ config, ... }:
{
  flake = {
    meta.users = {
      w963n = {
        email = "r.k.v.1225kaito@gmail.com";
        name = "Wallnut";
        username = "w963n";
      };
    };

    modules.nixos.w963n =
      { pkgs, ... }:
      {
        users.users.w963n = {
          isNormalUser = true;
          createHome = true;
          description = config.flake.meta.users.w963n.name;
          extraGroups = [
            "networkmanager"
            "wheel"
          ];
          shell = pkgs.zsh;
          initialPassword = "id";
        };

        programs.zsh.enable = true;

        nix.settings.trusted-users = [
          config.flake.meta.users.w963n.username
        ];
      };
  };
}
