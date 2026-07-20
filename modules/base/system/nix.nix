{
  flake.modules =
    let
      settings = {
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
    in
    {
      nixos.base = {
        nix = {
          extraOptions = ''
            connect-timeout = 5
            min-free = 128000000
            max-free = 1000000000
            fallback = true
          '';
          optimise.automatic = true;
          settings = settings // {
            auto-optimise-store = true;
          };
        };

        programs.nh = {
          enable = true;
          clean.enable = true;
          clean.extraArgs = "--keep-since 4d --keep 3";
        };
      };

      # auto-optimise-store / min-free / max-free are omitted on darwin: the
      # store GC knobs there behave differently, so rely on optimise.automatic.
      # programs.nh has no nix-darwin equivalent, so it stays NixOS-only.
      darwin.base = {
        nix = {
          extraOptions = ''
            connect-timeout = 5
            fallback = true
          '';
          optimise.automatic = true;
          inherit settings;
        };
      };
    };
}
