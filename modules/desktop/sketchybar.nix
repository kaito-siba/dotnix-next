{
  # Menu-bar daemon from a tap, no nixpkgs package. Identical tap entries from
  # sibling files collapse to one Brewfile line.
  flake.modules.darwin.desktop = {
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
}
