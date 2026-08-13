{
  flake.modules.homeManager.obs = {
    programs.obs-studio = {
      enable = true;
      # PipeWire capture covers wayland screens, so no extra plugins needed.
    };
  };
}
