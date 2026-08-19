{ config, ... }:
{
  flake = {
    meta.users = {
      k-nanchi = {
        email = "kaito@siba-service.jp";
        name = "k-nanchi";
        username = "k-nanchi";
      };
    };

    # The macOS account is created outside Nix, so
    # this only describes it. description is deliberately left alone: macOS
    # owns RealName.
    modules.darwin.k-nanchi =
      { pkgs, ... }:
      {
        users.users.k-nanchi = {
          home = "/Users/${config.flake.meta.users.k-nanchi.username}";
          shell = pkgs.zsh;
        };

        programs.zsh.enable = true;

        nix.settings.trusted-users = [
          config.flake.meta.users.k-nanchi.username
        ];
      };
  };
}
