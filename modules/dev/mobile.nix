{
  # React Native development: only the always-needed daemons and device
  # tools. JDKs and the Android SDK/emulator stay out of the profile on
  # purpose -- old apps need conflicting versions, so projects pin those
  # per-repo in a devshell (devenv/devbox are already on PATH).
  flake.modules = {
    homeManager.dev =
      { pkgs, lib, ... }:
      {
        home.packages =
          (with pkgs; [
            android-tools # adb / fastboot
            watchman # Metro's file watcher
          ])
          # The iOS side only exists where Xcode does.
          ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            pkgs.ios-deploy # install builds on a physical iPhone from the CLI
            pkgs.aria2 # xcodes downloads through it, several times faster
          ];
      };

    # Xcode version management. Xcode is a 10+GB Apple-signed bundle behind a
    # developer login, so nix cannot package it; xcodes is the nearest thing
    # to declarative -- `xcodes install 26.0`, `xcodes select` to switch, and
    # a `.xcode-version` file pins a repo to one.
    #
    # A brew rather than nixpkgs' xcodes, against the usual rule that terminal
    # tools come from nix: every download goes through Apple's developer
    # login, which Apple keeps changing -- 2.1.0 (2026-09) exists solely to
    # fix a 404 on login. nixpkgs still ships 1.6.2 from June 2025, two such
    # changes behind, and pulls swift and llvm into the closure for it.
    darwin.dev.homebrew.brews = [ "xcodes" ];
  };
}
