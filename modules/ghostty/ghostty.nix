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
          font-family = "Maple Mono NF CN";
          window-decoration = "none";
          window-padding-x = 12;
          window-padding-y = 12;
        };
      };
    };
}
