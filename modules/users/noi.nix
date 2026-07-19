{ config, ... }:
{
  flake = {
    meta.users = {
      noi = {
        email = "";
        name = "Noi";
        username = "noi";
      };
    };

    modules.nixos.noi =
      { pkgs, ... }:
      {
        users.users.noi = {
          isNormalUser = true;
          createHome = true;
          description = config.flake.meta.users.noi.name;
          extraGroups = [
            "networkmanager"
          ];
          shell = pkgs.zsh;
          initialPassword = "id";
        };

        programs.zsh.enable = true;
      };
  };
}
