{
  flake.modules = {
    # Menu-bar daemon from a tap, no nixpkgs package. Identical tap entries
    # from sibling files collapse to one Brewfile line.
    darwin.desktop = {
      homebrew = {
        taps = [
          {
            name = "felixkratz/formulae";
            trusted = true;
          }
        ];

        brews = [ "sketchybar" ];
      };
    };

    homeManager.desktop =
      { pkgs, lib, ... }:
      lib.mkIf pkgs.stdenv.isDarwin {
        xdg.configFile."sketchybar" = {
          source = ./config;
          recursive = true;
        };
      };
  };
}
