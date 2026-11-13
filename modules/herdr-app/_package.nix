{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  fontconfig,
  freetype,
  libxcb,
  libxkbcommon,
  vulkan-loader,
  wayland,
  herdr-core,
}:
let
  # release の target 名と、その tarball の hash。hash は
  # https://releases.herdr.dev/app/<version>/manifest.json の sha256。
  # macOS の release は Apple Silicon だけ。
  sources = {
    x86_64-linux = {
      target = "linux-x86_64";
      hash = "sha256-+Z4eBL6CwOELL2nudAPKNDhvSA2SUR31hlr0cD52Vd0=";
    };
    aarch64-darwin = {
      target = "macos-aarch64";
      hash = "sha256-NjPqXYaOpBD4Tfu3eiYgXeMx9N9S/bP7AGsrOXhFhFk=";
    };
  };
  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "herdr-app: ${stdenv.hostPlatform.system} 向けの release を入れていない");

  linux = {
    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
      copyDesktopItems
    ];

    buildInputs = [
      stdenv.cc.cc.lib
      fontconfig
      freetype
      libxcb
      libxkbcommon
    ];

    # 描画まわりは dlopen で読まれるので、NEEDED に現れなくても rpath に足す。
    runtimeDependencies = [
      vulkan-loader
      wayland
      libxkbcommon
    ];

    # herdr-app は自分の隣に herdr-app.svg がある時だけ自己更新する
    # (src/update.rs)。store は書き換えられないので、svg を隣に置かず
    # 自己更新を止める。
    # core は PATH から探されるので、同じ世代の herdr-core を先頭に固定する。
    installPhase = ''
      runHook preInstall

      install -Dm755 herdr-app $out/bin/herdr-app
      install -Dm644 herdr-app.svg $out/share/icons/hicolor/scalable/apps/herdr-app.svg
      wrapProgram $out/bin/herdr-app --prefix PATH : ${lib.makeBinPath [ herdr-core ]}

      runHook postInstall
    '';

    desktopItems = [
      (makeDesktopItem {
        name = "herdr-app";
        desktopName = "Herdr";
        comment = "Terminals and coding agents that keep running";
        exec = "herdr-app";
        icon = "herdr-app";
        categories = [ "Development" ];
        startupWMClass = "herdr-app";
      })
    ];
  };

  darwin = {
    # tarball の頂上が Herdr.app なので、unpack の後にその中へ入らせない。
    sourceRoot = ".";

    # 署名済みの bundle は中身を変えると壊れる (defaults/AGENTS.md)。wrapper も
    # 作らずそのまま置き、fixup もさせない。
    # - core は wrapper で PATH に足せないので、settings.json の core で固定する
    #   (herdr-app.nix)。
    # - 自己更新は止められない。bundle の隣、つまり store の中に書こうとして
    #   download の前に失敗するだけ (src/update.rs)。
    # - CLI は bundle の中の実行ファイルそのもの。
    installPhase = ''
      runHook preInstall

      mkdir -p $out/Applications $out/bin
      cp -R Herdr.app $out/Applications/
      ln -s ../Applications/Herdr.app/Contents/MacOS/Herdr $out/bin/herdr-app

      runHook postInstall
    '';

    dontFixup = true;
  };
in
stdenv.mkDerivation (
  finalAttrs:
  {
    pname = "herdr-app";
    # ソースビルドは Rust と Zig と ghostty の submodule が要るので、公式の
    # release バイナリを包む。nixpkgs 未収録なので手動 bump (version と hash を
    # 書き換える)。
    version = "0.1.15";

    src = fetchurl {
      url = "https://releases.herdr.dev/app/${finalAttrs.version}/herdr-app-${source.target}.tar.gz";
      inherit (source) hash;
    };

    dontStrip = true;

    meta = {
      description = "Desktop app for terminals and coding agents";
      homepage = "https://github.com/herdrdev/herdr-app";
      license = lib.licenses.asl20;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = builtins.attrNames sources;
      mainProgram = "herdr-app";
    };
  }
  // (if stdenv.hostPlatform.isDarwin then darwin else linux)
)
