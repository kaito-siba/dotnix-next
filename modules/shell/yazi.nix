{
  flake.modules.homeManager.shell =
    { config, pkgs, ... }:
    let
      yazi-plugins = pkgs.fetchFromGitHub {
        owner = "yazi-rs";
        repo = "plugins";
        rev = "de53d90cb2740f84ae595f93d0c4c23f8618a9e4";
        hash = "sha256-ixZKOtLOwLHLeSoEkk07TB3N57DXoVEyImR3qzGUzxQ=";
      };
    in
    {
      # Previewers yazi shells out to. Without these it falls back to plain
      # text for images, PDFs, video and archives.
      home.packages = with pkgs; [
        chafa
        exiftool
        ffmpeg
        imagemagick
        poppler-utils
        _7zz
      ];

      programs.yazi = {
        enable = true;
        enableZshIntegration = true;
        shellWrapperName = "y";

        settings = {
          mgr = {
            show_hidden = true;
          };
          preview = {
            max_width = 1000;
            max_height = 1000;
          };
        };

        plugins = {
          chmod = "${yazi-plugins}/chmod.yazi";
        };

        keymap = {
          mgr.prepend_keymap = [
            {
              on = [
                "c"
                "m"
              ];
              run = "plugin chmod";
              desc = "Chmod on selected files";
            }
          ];
        };
      };
    };
}
