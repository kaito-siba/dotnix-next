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
  #
  # Host-specific runtime state -- above all the monitor arrangement, which
  # the app persists as routing.mode = "custom" plus monitorRoutingOverrides
  # keyed by display UUID -- goes through omniwm.extraSettings instead: the
  # host declares it, it is merged over the shared file, and a switch then
  # writes back exactly what the app already believes, so the arrangement
  # survives activation.
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

    homeManager."desktop/darwin" =
      {
        pkgs,
        lib,
        config,
        ...
      }:
      let
        tomlFormat = pkgs.formats.toml { };
      in
      {
        options.omniwm.extraSettings = lib.mkOption {
          type = tomlFormat.type;
          default = { };
          description = ''
            Host-specific overrides merged (recursively; lists are replaced
            wholesale) over the shared OmniWM settings.toml.
          '';
        };

        config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          xdg.configFile."omniwm/settings.toml".source =
            if config.omniwm.extraSettings == { } then
              ./config/settings.toml
            else
              tomlFormat.generate "omniwm-settings.toml" (
                lib.recursiveUpdate (builtins.fromTOML (builtins.readFile ./config/settings.toml))
                  config.omniwm.extraSettings
              );
        };
      };
  };
}
