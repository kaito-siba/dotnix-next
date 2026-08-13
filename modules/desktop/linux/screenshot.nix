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
