{
  # rift (https://github.com/acsandmann/rift): scrolling window manager in the
  # niri mold, replacing aerospace. Runs without disabling SIP.
  #
  # The launchd service is imperative, once per machine:
  #   rift service install   (prompts for accessibility, then stops itself)
  #   rift service start
  flake.modules = {
    darwin.desktop = {
      homebrew = {
        taps = [
          {
            name = "acsandmann/tap";
            trusted = true;
          }
        ];

        brews = [ "rift" ];
      };
    };

    homeManager.desktop =
      { pkgs, lib, ... }:
      lib.mkIf pkgs.stdenv.isDarwin {
        xdg.configFile."rift/config.toml".source = ./config/config.toml;
      };
  };
}
