{
  # OmniWM (https://github.com/BarutSRB/OmniWM): the window manager, chosen
  # over rift after a trial. Signed and notarized, niri-parity actions, and
  # its built-in borders and menu-bar hiding replaced the separate borders
  # and hidden-bar tools this machine used to run.
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
