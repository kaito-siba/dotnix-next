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

    # The macOS account already exists and is created outside Nix, so this only
    # describes it. description is deliberately left alone: macOS owns RealName.
    modules.darwin.w963n =
      { pkgs, ... }:
      {
        users.users.w963n = {
          home = "/Users/${config.flake.meta.users.w963n.username}";
          shell = pkgs.zsh;
        };

        programs.zsh.enable = true;

        nix.settings.trusted-users = [
          config.flake.meta.users.w963n.username
        ];
      };
  };
}
