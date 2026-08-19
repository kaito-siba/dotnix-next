{
  # React Native development: only the always-needed daemons and device
  # tools. JDKs and the Android SDK/emulator stay out of the profile on
  # purpose -- old apps need conflicting versions, so projects pin those
  # per-repo in a devshell (devenv/devbox are already on PATH).
  flake.modules.homeManager.dev =
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
        ];
    };
}
