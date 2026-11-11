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
stdenv.mkDerivation (finalAttrs: {
  pname = "herdr-app";
  # ソースビルドは Rust と Zig と ghostty の submodule が要るので、公式の
  # release バイナリを包む。nixpkgs 未収録なので手動 bump (version と hash を
  # 書き換える)。hash は https://releases.herdr.dev/app/<version>/manifest.json
  # の sha256。
  version = "0.1.12";

  src = fetchurl {
    url = "https://releases.herdr.dev/app/${finalAttrs.version}/herdr-app-linux-x86_64.tar.gz";
    hash = "sha256-omXmySXEh0WEBnQf+gnS+g09S9QBo07YwBwzYQjlfB8=";
  };

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

  dontStrip = true;

  meta = {
    description = "Desktop app for terminals and coding agents";
    homepage = "https://github.com/herdrdev/herdr-app";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "herdr-app";
  };
})
