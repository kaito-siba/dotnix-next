{
  flake.modules.nixos.base = {
    nix = {
      extraOptions = ''
        connect-timeout = 5
        min-free = 128000000
        max-free = 1000000000
        fallback = true
      '';
      optimise.automatic = true;
      settings = {
        auto-optimise-store = true;
        trusted-users = [
          "root"
        ];
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        warn-dirty = false;
        tarball-ttl = 60 * 60 * 24;
      };
    };

    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 4d --keep 3";
    };

  };
}
