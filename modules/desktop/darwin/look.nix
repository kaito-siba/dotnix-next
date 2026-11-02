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
      pkgs,
      lib,
      ...
    }:
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
          };
        };
      };
    };
}
