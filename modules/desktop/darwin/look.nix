{
  # Look (https://github.com/kunkka19xx/look): keyboard-first launcher with
  # clipboard history, replacing raycast. The flake input is pinned to a
  # commit in flake.nix; its home-manager module installs the signed bundle
  # (copied into ~/Applications/Home Manager Apps) and merges the settings
  # below into ~/.look/config, which the app also writes to itself.
  #
  # Cmd+Space is Look's default hotkey and collides with Spotlight; disable
  # Spotlight's shortcut under System Settings > Keyboard > Keyboard
  # Shortcuts > Spotlight once per machine. Accessibility / Automation grants
  # are TCC state and stay manual as well.
  flake.modules.homeManager."desktop/darwin" =
    {
      inputs,
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Prints the JSON a Look tile reads: free space on the root volume.
      diskFree = pkgs.writeShellScript "look-tile-disk-free" ''
        free=$(/bin/df -h / | /usr/bin/awk 'NR==2 {print $4}')
        printf '{"value":"%s","caption":"DISK FREE","icon":"internaldrive"}' "$free"
      '';

      # Quits Look and starts it again, e.g. to pick up a background image
      # swapped in place. Waits for the old process to go: `open` while it is
      # still shutting down would only re-focus the dying instance.
      restartLook = pkgs.writeShellScript "look-restart" ''
        /usr/bin/osascript -e 'quit app "Look"'
        for _ in $(seq 50); do
          /usr/bin/pgrep -xq Look || break
          sleep 0.1
        done
        /usr/bin/open -a Look
      '';
    in
    {
      imports = [ inputs.look.homeModules.default ];

      config = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        programs.lookapp = {
          enable = true;
          settings = {
            # On by default on macOS: live Google suggestions and a
            # DuckDuckGo / Wikipedia card as you type. Keep typing local.
            ai_enabled = false;
            clipboard_history_limit = 200;
            text_editor = "nvim";
            terminal = "ghostty";

            # --- look -------------------------------------------------------
            # The image is personal and stays out of the repo: drop any picture
            # at this path. Look doesn't expand `~`, so the path is absolute.
            # Each super-action tile shows its own slice of the image under a
            # frosted overlay, so bar and tiles read as one picture.
            # Look decodes the image once and re-reads it only when this path
            # changes, so after swapping the file in place, restart Look.
            ui_background_image = "${config.home.homeDirectory}/Pictures/wallpapers/look.jpg";
            ui_background_image_mode = "fill";
            ui_background_image_opacity = 0.8;
            ui_background_image_blur = 5;

            # Serif text (Charter ships with macOS) on a warm, dark frost.
            ui_font_name = "Charter";
            ui_font_size = 15;
            ui_tint_red = 0.12;
            ui_tint_green = 0.08;
            ui_tint_blue = 0.07;
            ui_tint_opacity = 0.35;
            ui_border_opacity = 0.18;
            ui_surface_radius = 1.0;
            inner_gap = 12;

            # Running apps as numbered icons inside the search bar, and the
            # tile strip on the empty home screen.
            running_apps_placement = "right";
            super_actions_enabled = true;
          };
        };

        # Custom commands: type the name in Look and press Enter. Look starts
        # each step in its own session (setsid), so the restart survives the
        # app quitting underneath it.
        home.file.".look/sources/look.toml".text = ''
          [restart-look]
          name = "Restart Look"
          icon = "arrow.clockwise"
          do   = ["${restartLook}"]
        '';

        # Tile layout for the empty home screen. Look only seeds this file when
        # it is missing and never writes it back, so a read-only symlink is
        # fine; `force` replaces the copy it seeded on first run.
        home.file.".look/super-actions.toml" = {
          force = true;
          text = ''
            layout = [
                "lslot   lslot   shutdown   keepawake   weather",
                "lslot   lslot   disk       lock        weather",
            ]

            [tiles.disk]
            value   = "${diskFree}"
            refresh = "5m"

            # Sleeps the display, which locks when Lock Screen asks for a
            # password after sleep.
            [tiles.lock]
            press    = "pmset displaysleepnow"
            title    = "Lock"
            icon     = "lock.fill"
            mnemonic = "L"
          '';
        };
      };
    };
}
