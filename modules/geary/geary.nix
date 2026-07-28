{
  # GNOME mail client (the Linux counterpart of thunderbird on darwin hosts).
  flake.modules.homeManager.geary =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.geary ];
    };
}
