{
  # The trackpad keeps natural scrolling while the mouse wheel is reversed:
  # macOS has a single switch for both, Scroll Reverser splits them per
  # device. Preference keys were read back from a machine that had it set up
  # by hand (defaults read com.pilotmoon.scroll-reverser).
  #
  # Accessibility / input-monitoring permission is TCC state and stays a
  # one-time manual grant per machine.
  flake.modules.homeManager."desktop/darwin" =
    { pkgs, lib, ... }:
    lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      home.packages = [ pkgs.scroll-reverser ];

      targets.darwin.defaults."com.pilotmoon.scroll-reverser" = {
        HasRunBefore = true;
        HideIcon = true;
        InvertScrollingOn = true;
        ReverseMouse = true;
        ReverseTrackpad = false;
      };

      launchd.agents.scroll-reverser = {
        enable = true;
        config = {
          Label = "com.pilotmoon.scroll-reverser.autostart";
          ProgramArguments = [
            "${pkgs.scroll-reverser}/Applications/Scroll Reverser.app/Contents/MacOS/Scroll Reverser"
          ];
          RunAtLoad = true;
        };
      };
    };
}
