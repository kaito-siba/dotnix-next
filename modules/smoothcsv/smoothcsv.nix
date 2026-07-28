{
  flake.modules.homeManager.smoothcsv =
    { pkgs, ... }:
    let
      pname = "smoothcsv";
      version = "3.22.0";

      src = pkgs.fetchurl {
        url = "https://github.com/kohii/smoothcsv3/releases/download/v${version}/SmoothCSV_${version}_amd64.AppImage";
        hash = "sha256-d9IvrHjJfUdU5jOaYQIfMX0i1yar0XZANHenQW0jhGE=";
      };

      contents = pkgs.appimageTools.extractType2 { inherit pname version src; };

      smoothcsv = pkgs.appimageTools.wrapType2 {
        inherit pname version src;
        meta = {
          mainProgram = pname;
        };
      };

      smoothcsvWayland = pkgs.writeShellApplication {
        name = "smoothcsv-wayland";
        runtimeInputs = [ ];
        text = ''
          export XDG_DATA_DIRS=${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}:$XDG_DATA_DIRS;
          export GIO_MODULE_DIR="${pkgs.glib-networking}/lib/gio/modules/";
          exec ${smoothcsv}/bin/smoothcsv "$@"
        '';
      };
    in
    {
      home.packages = [
        smoothcsv
        smoothcsvWayland
        contents
      ];

      xdg.enable = true;
      xdg.desktopEntries.${pname} = {
        name = "SmoothCSV";
        genericName = "CSV Editor";
        comment = "SmoothCSV 3";
        exec = "${smoothcsvWayland}/bin/smoothcsv-wayland %U";
        terminal = false;
        categories = [
          "Utility"
          "Office"
        ];
        icon = "${contents}/${pname}-app.png";
      };

      # Open csv files from yazi with smoothcsv by default.
      programs.yazi.settings = {
        opener.smoothcsv = [
          {
            run = ''setsid -f smoothcsv-wayland "$@" >/dev/null 2>&1'';
            orphan = true;
            desc = "SmoothCSV";
          }
        ];
        open.prepend_rules = [
          {
            url = "*.csv";
            use = [
              "smoothcsv"
              "edit"
              "reveal"
            ];
          }
        ];
      };
    };
}
