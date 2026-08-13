{ config, ... }:
{
  flake = {
    meta.users = {
      rkv12 = {
        email = "kaito@siba-service.jp";
        name = "rkv12";
        username = "rkv12";
      };
    };

    # The account already exists on radiata, so no initialPassword: mutable
    # users keep the password that was set imperatively.
    modules.nixos.rkv12 =
      { pkgs, ... }:
      {
        users.users.rkv12 = {
          isNormalUser = true;
          createHome = true;
          description = config.flake.meta.users.rkv12.name;
          extraGroups = [
            "networkmanager"
            "wheel"
            "audio"
            "video"
            "docker"
            "libvirtd"
            "kvm"
          ];
          shell = pkgs.zsh;
        };

        programs.zsh.enable = true;

        nix.settings.trusted-users = [
          config.flake.meta.users.rkv12.username
        ];
      };
  };
}
