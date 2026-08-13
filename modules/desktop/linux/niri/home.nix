{
  # The shared config includes outputs.kdl, which each host overrides with its
  # own monitor layout (see hosts/*/).
  flake.modules.homeManager."desktop/linux" = {
    xdg.configFile."niri/config.kdl".source = ./config/config.kdl;
    xdg.configFile."niri/outputs.kdl".source = ./config/outputs.kdl;

    # Appearance overrides included from config.kdl. The filename is kept from
    # the v4 noctalia-template era; the content is now a static catppuccin
    # mocha accent file owned by this module, so the niri config loads even on
    # hosts without the noctalia module.
    xdg.configFile."niri/noctalia-transparent.kdl".source = ./niri-appearance.kdl;
  };
}
