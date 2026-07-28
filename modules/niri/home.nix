{
  # The shared config includes outputs.kdl, which each host overrides with its
  # own monitor layout (see hosts/*/). noctalia-transparent.kdl is generated at
  # runtime by noctalia's template hook.
  flake.modules.homeManager.niri = {
    xdg.configFile."niri/config.kdl".source = ./config/config.kdl;
    xdg.configFile."niri/outputs.kdl".source = ./config/outputs.kdl;
  };
}
