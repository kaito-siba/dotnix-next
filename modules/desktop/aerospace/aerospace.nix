{
  flake.modules = {
    darwin.desktop = {
      homebrew = {
        taps = [
          {
            name = "nikitabobko/tap";
            trusted = true;
          }
        ];

        casks = [ "aerospace" ];
      };
    };

    homeManager.desktop =
      { pkgs, lib, ... }:
      lib.mkIf pkgs.stdenv.isDarwin {
        xdg.configFile."aerospace" = {
          source = ./config;
          recursive = true;
        };
      };
  };
}
