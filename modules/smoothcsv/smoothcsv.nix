{
  # SmoothCSV 3, pinned to one upstream release for both platforms: linux
  # runs the AppImage, darwin the .app archive that upstream publishes for
  # its Tauri updater (no dmg unpacking needed). Bump `version` and the two
  # hashes together.
  flake.modules.homeManager.smoothcsv =
    { pkgs, lib, ... }:
    let
      pname = "smoothcsv";
      version = "3.24.0";

      src = pkgs.fetchurl {
        url = "https://github.com/kohii/smoothcsv3/releases/download/v${version}/SmoothCSV_${version}_amd64.AppImage";
        hash = "sha256-50Y15nuWWSqMg3z94r5CY8nRtW0DSSmDdFbyiLVLYuw=";
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
          export XDG_DATA_DIRS=${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}:''${XDG_DATA_DIRS:-};
          export GIO_MODULE_DIR="${pkgs.glib-networking}/lib/gio/modules/";
          exec ${smoothcsv}/bin/smoothcsv "$@"
        '';
      };

      smoothcsvApp = pkgs.stdenvNoCC.mkDerivation {
        pname = "${pname}-app";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://github.com/kohii/smoothcsv3/releases/download/v${version}/SmoothCSV_universal.app.tar.gz";
          hash = "sha256-mIzeCt4c1jSNTb739Cd9nzZZCJ9/hNmzEK/5uKEZyCk=";
        };

        sourceRoot = ".";
        dontConfigure = true;
        dontBuild = true;
        # The bundle is signed; the default fixup would strip the binary and
        # break the signature.
        dontFixup = true;

        installPhase = ''
          mkdir -p $out/Applications
          cp -R SmoothCSV.app $out/Applications/
        '';
      };

      # Open csv files from yazi with smoothcsv by default.
      yaziIntegration = run: {
        programs.yazi.settings = {
          opener.smoothcsv = [
            {
              inherit run;
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
    in
    lib.mkMerge [
      (lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
        lib.mkMerge [
          {
            # The desktop entry's icon references ${contents} by store path,
            # which keeps the extracted AppImage alive without installing it
            # into the profile.
            home.packages = [
              smoothcsv
              smoothcsvWayland
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
          }
          (yaziIntegration ''setsid -f smoothcsv-wayland "$@" >/dev/null 2>&1'')
        ]
      ))

      (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (
        lib.mkMerge [
          {
            home.packages = [ smoothcsvApp ];
          }
          # `open -a` by store path rather than by name: it works even before
          # LaunchServices has indexed the linked application folder.
          (yaziIntegration ''open -a "${smoothcsvApp}/Applications/SmoothCSV.app" "$@"'')
        ]
      ))
    ];
}
