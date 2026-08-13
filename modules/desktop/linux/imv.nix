{
  # Default lightweight image viewer for the wayland session.
  flake.modules.homeManager."desktop/linux" =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.imv ];
    };
}
