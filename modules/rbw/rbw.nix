{
  # Bitwarden CLI client. pinentry-gnome3 makes this Linux-desktop specific.
  flake.modules.homeManager.rbw =
    { pkgs, ... }:
    {
      programs.rbw = {
        enable = true;
        settings = {
          email = "r.k.v.1225kaito@icloud.com";
          pinentry = pkgs.pinentry-gnome3;
        };
      };
    };
}
