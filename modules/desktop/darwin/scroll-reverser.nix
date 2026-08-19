{
  # The trackpad keeps natural scrolling while the mouse wheel is reversed:
  # macOS has a single switch for both, Scroll Reverser splits them per
  # device.
  #
  # The app is a cask, not the nixpkgs package: the nixpkgs bundle fails
  # codesign ("a sealed resource is missing or invalid") so Gatekeeper
  # refuses to launch it, and an accessibility app needs its developer
  # signature intact anyway for the TCC grant to survive updates. Nix
  # contributes the preferences and the autostart.
  #
  # Preference keys were read back from a machine that had it set up by hand
  # (defaults read com.pilotmoon.scroll-reverser). Accessibility /
  # input-monitoring permission is TCC state and stays a one-time manual
  # grant per machine.
  flake.modules = {
    darwin.desktop = {
      homebrew.casks = [ "scroll-reverser" ];
    };

    homeManager."desktop/darwin" =
      { pkgs, lib, ... }:
      lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
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
              "/Applications/Scroll Reverser.app/Contents/MacOS/Scroll Reverser"
            ];
            RunAtLoad = true;
          };
        };
      };
  };
}
