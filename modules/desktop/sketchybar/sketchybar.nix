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

    # After changing the config, restart the service:
    #   brew services restart sketchybar
    # Do NOT use `sketchybar --reload`: with the config symlinked into the
    # store it resets the bar to defaults and then silently fails to re-run
    # the config, leaving an empty bar. Executing the config at daemon
    # startup works fine.
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
