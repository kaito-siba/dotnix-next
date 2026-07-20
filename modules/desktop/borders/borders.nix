{
  flake.modules = {
    # Window-border overlay daemon from a tap, no nixpkgs package.
    darwin.desktop = {
      homebrew = {
        taps = [
          {
            name = "felixkratz/formulae";
            trusted = true;
          }
        ];

        brews = [ "borders" ];
      };
    };

    homeManager.desktop = {
      xdg.configFile."borders" = {
        source = ./config;
        recursive = true;
      };
    };
  };
}
