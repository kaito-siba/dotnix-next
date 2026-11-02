{
  # GUI applications that are only an install: no settings, no siblings on
  # Linux. nixpkgs ships the vendor's signed .app for each, so they land in
  # ~/Applications/Home Manager Apps via copyApps and show up in Spotlight.
  # Their in-app updaters fail against the read-only store, which is the
  # point: the version is whatever flake.lock says.
  nixpkgs.allowedUnfreePackages = [
    "google-chrome"
    "notion-app"
    "zoom"
  ];

  flake.modules.homeManager."desktop/darwin" =
    { pkgs, lib, ... }:
    lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      home.packages = with pkgs; [
        google-chrome
        notion-app
        zoom-us
      ];
    };
}
