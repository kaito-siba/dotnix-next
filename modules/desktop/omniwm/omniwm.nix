{
  # OmniWM (https://github.com/BarutSRB/OmniWM): trial alongside rift, to
  # decide which scrolling window manager this machine keeps. Only one may
  # manage windows at a time -- stop rift's service before launching this.
  #
  # Its settings.toml is left GUI-managed during the trial: the app live-edits
  # it, so vendoring now would fight the app the way karabiner's config would.
  # If OmniWM wins, vendor the settled config next to this file and drop rift.
  flake.modules.darwin.desktop = {
    homebrew = {
      taps = [
        {
          name = "BarutSRB/tap";
          trusted = true;
        }
      ];

      casks = [ "omniwm" ];
    };
  };
}
