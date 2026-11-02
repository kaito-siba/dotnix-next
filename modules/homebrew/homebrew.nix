{
  # Homebrew is the last resort, not the default: only applications that
  # nixpkgs cannot provide on darwin stay casks, and each is declared by the
  # module that needs it (activitywatch, scroll-reverser, xcodes, mysql-shell,
  # google-japanese-ime). Everything else, GUI applications included, comes
  # from nixpkgs so that it is pinned by flake.lock and reviewed upstream.
  #
  # Nothing updates on its own. Casks cannot be pinned to a version, so the
  # next best thing is to never upgrade implicitly: a cask only moves when the
  # Brewfile changes and a switch is run on purpose. Casks with their own
  # updater (Sparkle etc.) still update themselves; that is theirs to do.
  flake.modules.darwin.homebrew =
    { lib, ... }:
    {
      homebrew = {
        enable = true;

        # Declared state is the whole state: anything brew-installed and not
        # listed here is uninstalled on activation. "uninstall" rather than
        # "zap" so removal never takes an application's data with it.
        onActivation = {
          autoUpdate = false;
          cleanup = "uninstall";
          upgrade = false;
        };

        # Third-party taps are declared by the modules that consume them, with
        # trusted = true: Homebrew 6 refuses to load anything from an untrusted
        # tap during activation, and `brew trust` on the command line does not
        # carry over -- the trust has to be in the generated Brewfile.
      };

      # Homebrew goes last on PATH, not first as `brew shellenv` would have it,
      # so a tool that exists in both places resolves to the nix one.
      environment.systemPath = lib.mkAfter [
        "/opt/homebrew/bin"
        "/opt/homebrew/sbin"
      ];
    };
}
