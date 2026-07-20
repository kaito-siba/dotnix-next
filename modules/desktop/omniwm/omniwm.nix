{
  # OmniWM (https://github.com/BarutSRB/OmniWM): trial alongside rift, to
  # decide which scrolling window manager this machine keeps. Only one may
  # manage windows at a time -- stop rift's service before launching this.
  #
  # settings.toml is the file the app generated on first launch with the niri
  # muscle memory remapped onto it (Alt+HJKL, Alt+R width presets, Alt+O
  # overview...). The app live-reloads it on change. The GUI also writes to
  # it: a GUI edit replaces the symlink and is rolled back at the next switch
  # (backed up as .before-nix), so changes flow through this file. When
  # porting a setting the GUI wrote, read the backup for the exact schema.
  flake.modules = {
    darwin.desktop = {
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

    homeManager.desktop =
      { pkgs, lib, ... }:
      lib.mkIf pkgs.stdenv.isDarwin {
        xdg.configFile."omniwm/settings.toml".source = ./config/settings.toml;
      };
  };
}
