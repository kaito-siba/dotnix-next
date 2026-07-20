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

    homeManager.desktop = {
      xdg.configFile."aerospace" = {
        source = ./config;
        recursive = true;
      };
    };
  };
}
