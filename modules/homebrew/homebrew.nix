{
  # Homebrew keeps managing GUI applications: casks that ship system extensions,
  # login items or Sparkle updaters do not survive being rebuilt from nixpkgs.
  # Everything reachable from a terminal should come from nix instead.
  #
  # Two things live here: the machinery, and an inventory of applications that
  # are only an install -- no settings, no second platform, no siblings. The
  # moment one grows any of those it graduates to its own module, the way
  # obsidian, ghostty and the desktop session did. Taps and casks contributed
  # by those modules merge into the same Brewfile.
  flake.modules.darwin.homebrew =
    { lib, ... }:
    {
      homebrew = {
        enable = true;

        # Activation also updates: not everything here self-updates (formulae
        # like sketchybar never do, and casks such as activitywatch carry no
        # updater), so a switch upgrades the whole brew state along with it.
        # The cost is that activation reaches out to the network and takes
        # longer; when offline, expect the brew step to fail.
        #
        # Declared state is the whole state: anything installed by hand and not
        # listed here is uninstalled on activation. "uninstall" rather than
        # "zap" so removal never takes an application's data with it.
        onActivation = {
          autoUpdate = true;
          cleanup = "uninstall";
          upgrade = true;
        };

        # Third-party taps are declared by the modules that consume them, with
        # trusted = true: Homebrew 6 refuses to load anything from an untrusted
        # tap during activation, and `brew trust` on the command line does not
        # carry over -- the trust has to be in the generated Brewfile.
        brews = [
          "mas" # Mac App Store CLI, has no nixpkgs equivalent
        ];

        casks = [
          # Browsers
          "google-chrome"
          "zen"

          # Communication
          "slack"
          "zoom"

          # Notes and knowledge
          "anki"
          "notion"

          # Media
          "spotify"

          # Design
          "figma"

          # Hardware and peripherals
          "fujitsu-scansnap-home"

          # AI
          "claude"
        ];
      };

      # Homebrew goes last on PATH, not first as `brew shellenv` would have it,
      # so a tool that exists in both places resolves to the nix one.
      environment.systemPath = lib.mkAfter [
        "/opt/homebrew/bin"
        "/opt/homebrew/sbin"
      ];
    };
}
