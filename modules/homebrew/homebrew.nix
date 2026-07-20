{
  # Homebrew keeps managing GUI applications: casks that ship system extensions,
  # login items or Sparkle updaters do not survive being rebuilt from nixpkgs.
  # Everything reachable from a terminal should come from nix instead.
  flake.modules.darwin.homebrew =
    { lib, ... }:
    {
      homebrew = {
        enable = true;

        # Declared state is the whole state: anything installed by hand and not
        # listed here is uninstalled on activation. "uninstall" rather than
        # "zap" so removal never takes an application's data with it.
        #
        # Updating is left to the casks themselves -- nearly all of them carry
        # Sparkle, which is the reason they are casks and not nix packages --
        # so activation stays fast and does not reach out to the network.
        onActivation = {
          autoUpdate = false;
          cleanup = "uninstall";
          upgrade = false;
        };

        taps = [
          "felixkratz/formulae" # borders, sketchybar
          "nikitabobko/tap" # aerospace
          "lihaoyun6/tap" # quickrecorder
        ];

        brews = [
          "mas" # Mac App Store CLI, has no nixpkgs equivalent
        ];

        casks = [
          # Window management and input
          "aerospace"
          "hammerspoon"
          "karabiner-elements"
          "keyboardcleantool"
          "raycast"
          "scroll-reverser"
          "hiddenbar"

          # Terminals
          "ghostty"
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
          "obsidian"

          # Media
          "iina"
          "spotify"
          "quickrecorder"
          "shottr"

          # Photography
          "amazon-photos"
          "fujifilm-x-raw-studio"
          "rawtherapee"

          # Design
          "figma"

          # Input methods and audio routing
          "google-japanese-ime"
          "blackhole-16ch"

          # Hardware and peripherals
          "fujitsu-scansnap-home"
          "logitech-options"

          # Utilities
          "appcleaner"
          "smoothcsv"
          "session-manager-plugin"

          # Networking
          "tailscale-app"

          # AI
          "claude"

          # Fonts
          "font-fira-code-nerd-font"
          "font-hack-nerd-font"
          "font-meslo-lg-nerd-font"
          "font-ricty-diminished"
          "font-symbols-only-nerd-font"
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
