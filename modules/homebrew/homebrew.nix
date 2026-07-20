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

        # Updating is left to the casks themselves -- nearly all of them carry
        # Sparkle, which is the reason they are casks and not nix packages --
        # so activation stays fast and does not reach out to the network.
        #
        # Declared state is the whole state: anything installed by hand and not
        # listed here is uninstalled on activation. "uninstall" rather than
        # "zap" so removal never takes an application's data with it.
        onActivation = {
          autoUpdate = false;
          cleanup = "uninstall";
          upgrade = false;
        };

        # Homebrew 6 refuses to load anything from an untrusted third-party tap
        # during activation, and `brew trust` on the command line does not carry
        # over -- the trust has to be in the Brewfile that nix-darwin generates.
        taps = [
          {
            name = "lihaoyun6/tap"; # quickrecorder
            trusted = true;
          }
        ];

        brews = [
          "mas" # Mac App Store CLI, has no nixpkgs equivalent
        ];

        casks = [
          # Terminals. ghostty comes from nixpkgs (modules/ghostty); this one
          # stays a cask because it deliberately tracks nightly.
          "wezterm@nightly"

          # Browsers
          "google-chrome"
          "zen"

          # Communication
          "discord"
          "slack"
          "zoom"

          # Notes and knowledge
          "anki"
          "notion"

          # Media
          "spotify"
          "quickrecorder"

          # Design
          "figma"

          # Hardware and peripherals
          "fujitsu-scansnap-home"
          "logitech-options"

          # Utilities
          "smoothcsv"

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
