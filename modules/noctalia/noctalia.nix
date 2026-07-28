{
  flake.modules.homeManager.noctalia =
    { inputs, pkgs, ... }:
    {
      imports = [ inputs.noctalia.homeModules.default ];

      home.packages = with pkgs; [
        gpu-screen-recorder
        wtype
        gradia

        # theme generation for the user templates below
        matugen

        # for screen toolkit
        grim
        slurp
        wl-clipboard
        tesseract
        imagemagick
        zbar
        curl
        translate-shell
        wl-screenrec
        ffmpeg
        gifski

        # for file search
        fd
      ];

      programs.noctalia-shell = {
        enable = true;
        plugins = {
          sources = [
            {
              enabled = true;
              name = "Official Noctalia Plugins";
              url = "https://github.com/noctalia-dev/noctalia-plugins";
            }
          ];
          states = {
            screen-recorder = {
              enabled = true;
              sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
            };
            pomodoro = {
              enabled = true;
              sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
            };
            currency-exchange = {
              enabled = true;
              sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
            };
            translator = {
              enabled = true;
              sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
            };
            custom-commands = {
              enabled = true;
              sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
            };
            model-usage = {
              enabled = true;
              sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
            };
            screen-toolkit = {
              enabled = true;
              sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
            };
            file-search = {
              enabled = true;
              sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
            };
          };
          version = 1;
        };

        pluginSettings = {
          pomodoro = {
            workDuration = 25;
            shortBreakDuration = 5;
            longBreakDuration = 15;
            sessionsBeforeLongBreak = 4;
            autoStartBreaks = true;
            autoStartWork = true;
            compactMode = true;
          };
          custom-commands = {
            commands = [
              {
                name = "Mirror Focused Screen";
                command = "wl-mirror \"$(niri msg --json focused-output | jq -r .name)\"";
                icon = "screen-share";
              }
              {
                name = "Restart Slack";
                command = "pkill -HUP slack && slack";
                icon = "brand-slack";
              }
            ];
          };
          model-usage = {
            refreshIntervalSec = 30;
            barCycleIntervalSec = 5;
            providers = {
              codex = {
                enabled = true;
              };
              claude = {
                enabled = true;
              };
            };
            barMetric = "usage";
          };
        };

        # App theming templates were dropped in favour of the static catppuccin
        # themes the shared modules ship. Only the niri include remains, since
        # config.kdl unconditionally includes noctalia-transparent.kdl.
        user-templates = {
          config = { };
          templates = {
            niri-transparent = {
              input_path = "~/.config/noctalia/templates/niri-transparent.kdl";
              output_path = "~/.config/niri/noctalia-transparent.kdl";
            };
          };
        };
      };

      # for dynamic gnome color scheme switching with theme hook
      home.file.".local/bin/set-gnome-color-schema" = {
        source = ./scripts/set-gnome-color-schema;
        executable = true;
      };

      xdg.configFile."noctalia/settings.json".source = ./settings.json;
      xdg.configFile."noctalia/templates".source = ./templates;

      # Wallpapers and the avatar are vendored in the repo; settings.json
      # points at these store-backed links.
      xdg.configFile."noctalia/wallpapers".source = ../../assets/wallpapers;
      xdg.configFile."noctalia/avatar.jpg".source = ../../assets/icons/icon_1.jpg;
    };
}
