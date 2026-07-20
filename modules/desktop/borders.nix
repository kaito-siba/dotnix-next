{
  # Window-border overlay daemon from a tap, no nixpkgs package.
  flake.modules.darwin.desktop = {
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
}
