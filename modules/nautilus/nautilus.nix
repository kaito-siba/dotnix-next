{
  # File manager. gvfs supplies trash / mtp / network mounts, glib the gio CLI.
  flake.modules = {
    nixos.nautilus = {
      services.gvfs.enable = true;
    };

    homeManager.nautilus =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          nautilus
          glib
        ];

        # Reveal the selected file in nautilus from within yazi.
        programs.yazi.settings.opener.reveal = [
          {
            run = ''setsid -f nautilus "$@" >/dev/null 2>&1'';
            orphan = true;
            desc = "Reveal in Nautilus";
          }
        ];
      };
  };
}
