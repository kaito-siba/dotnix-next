{
  nixpkgs.allowedUnfreePackages = [
    "slack"
    "discord"
    "google-chrome"
  ];

  # GUI applications with no configuration of their own. Anything that grows
  # real configuration should move into its own module.
  flake.modules.homeManager.desktop-apps =
    { pkgs, pkgs-unstable, ... }:
    {
      home.packages =
        (with pkgs; [
          dbeaver-bin
          zeal
          geary
          imv
        ])
        ++ (with pkgs-unstable; [
          slack
          discord
          google-chrome
        ]);
    };
}
