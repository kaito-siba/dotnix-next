{
  flake.modules.homeManager."desktop/linux" =
    { pkgs, config, ... }:
    {
      home.packages = with pkgs; [
        grim
        slurp
        swappy
      ];

      xdg.userDirs = {
        enable = true;
        createDirectories = true;
        # The 26.05 default. XDG_*_DIR env vars are not the spec's interface
        # (user-dirs.dirs / xdg-user-dir are), and nothing here reads them.
        setSessionVariables = false;
      };

      xdg.configFile."swappy/config".text = ''
        [Default]
        save_dir=${config.xdg.userDirs.pictures}/Screenshots
        save_filename_format=%Y-%m-%d-%H%M%S.png
        show_panel=true
        early_exit=false
        line_size=3
        text_size=16
        window_radius=8
        image_quality=100
      '';
    };
}
