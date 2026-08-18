{
  # The darwin incumbent while aerion is on trial; Linux hosts use geary
  # instead, so this half only applies on darwin.
  #
  # nixpkgs ships a real Thunderbird.app on darwin -- the unwrapped build comes
  # straight from the binary cache, only the wrapper is built locally -- so this
  # does not need to be a cask. The self-updater would fail against a read-only
  # store anyway, and DisableAppUpdate turns it off through the enterprise
  # policy the wrapper bakes into the bundle, the same bargain obsidian makes.
  flake.modules.homeManager.mail =
    { pkgs, lib, ... }:
    lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      home.packages = [
        (pkgs.thunderbird.override {
          extraPolicies.DisableAppUpdate = true;
        })
      ];
    };
}
