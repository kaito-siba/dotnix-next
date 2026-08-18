{
  # Aerion (https://github.com/hkdb/aerion): Wails + Svelte 製のメールクライアント。
  # nixpkgs 未収録のため、リリースの成果物をプラットフォーム別に取り込む。
  flake.modules.homeManager.mail =
    { pkgs, ... }:
    let
      version = "0.3.2";

      meta = {
        description = "Modern, cross-platform email client built with Wails + Svelte";
        homepage = "https://aerion.3df.io";
        license = pkgs.lib.licenses.asl20;
        mainProgram = "aerion";
      };

      # Linux バイナリを autoPatchelf で取り込む。
      linuxPkg = pkgs.stdenv.mkDerivation {
        pname = "aerion";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://github.com/hkdb/aerion/releases/download/v${version}/aerion-linux-amd64.tar.gz";
          hash = "sha256-9MiCCwPG6CpceGVuCUIS3TQpurAe9ODLNvDjRtI3ECA=";
        };

        sourceRoot = ".";

        nativeBuildInputs = with pkgs; [
          autoPatchelfHook
          # webview 向けに gsettings schema / gio modules / pixbuf loader を配線する
          wrapGAppsHook3
        ];

        buildInputs = with pkgs; [
          gtk3
          webkitgtk_4_1
          libsoup_3
          glib
          gdk-pixbuf
          # libsoup の TLS (HTMLメール内リモートコンテンツ取得) 用
          glib-networking
          gsettings-desktop-schemas
        ];

        installPhase = ''
          runHook preInstall
          install -Dm755 aerion $out/bin/aerion
          install -Dm644 io.github.hkdb.Aerion.desktop \
            $out/share/applications/io.github.hkdb.Aerion.desktop
          install -Dm644 io.github.hkdb.Aerion.png \
            $out/share/pixmaps/io.github.hkdb.Aerion.png
          runHook postInstall
        '';

        meta = meta // {
          platforms = [ "x86_64-linux" ];
        };
      };

      # macOS は署名済み Aerion.app をそのまま配置する。home-manager が
      # ~/Applications/Home Manager Apps にリンクするので Spotlight からも起動できる。
      darwinPkg = pkgs.stdenv.mkDerivation {
        pname = "aerion";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://github.com/hkdb/aerion/releases/download/v${version}/Aerion-darwin-arm64.zip";
          hash = "sha256-bEaIAhQYaCMgRcORUA/QGgljofSa/pD0nmgrnJ5aFNw=";
        };

        nativeBuildInputs = [ pkgs.unzip ];
        sourceRoot = ".";

        installPhase = ''
          runHook preInstall
          mkdir -p $out/Applications
          cp -R Aerion.app $out/Applications/
          runHook postInstall
        '';

        meta = meta // {
          platforms = [ "aarch64-darwin" ];
        };
      };
    in
    {
      home.packages = [
        (if pkgs.stdenv.hostPlatform.isDarwin then darwinPkg else linuxPkg)
      ];
    };
}
