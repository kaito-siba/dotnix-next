{ config, ... }:
{
  flake.modules.homeManager.ghostty =
    { pkgs, lib, ... }:
    {
      programs.ghostty = {
        enable = true;

        # nixpkgs only source-builds ghostty for Linux; the macOS app is an
        # Xcode project, packaged from the official release as ghostty-bin.
        package = lib.mkIf pkgs.stdenv.isDarwin pkgs.ghostty-bin;

        # Settings are attrs (not a raw config file) so theming modules such
        # as noctalia can override individual keys per host.
        settings = {
          theme = "dark: Catppuccin Mocha, light:Catppuccin Latte";
          font-family = config.flake.meta.fonts.coding;
          window-padding-x = 12;
          window-padding-y = 12;
        }
        # Same intent on both platforms -- no titlebar -- but the macOS knob
        # has to be the other one. `window-decoration = none` strips the whole
        # window frame there, and a frameless NSWindow is not a standard
        # accessibility window, so omniwm (which discovers windows through the
        # accessibility API) silently skips it. `hidden` drops the titlebar and
        # keeps the frame and rounded corners.
        // lib.optionalAttrs pkgs.stdenv.isDarwin { macos-titlebar-style = "hidden"; }
        // lib.optionalAttrs pkgs.stdenv.isLinux { window-decoration = "none"; };
      };
    };
}
