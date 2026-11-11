{
  lib,
  stdenv,
  fetchurl,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "herdr-core";
  # nixpkgs 未収録のバイナリなので手動 bump (version と hash を書き換える)。
  # hash は https://releases.herdr.dev/core/<version>/manifest.json の sha256。
  # herdr-app の distribution/core-version が要求する最低 version を下回らせない。
  version = "0.1.17";

  src = fetchurl {
    url = "https://releases.herdr.dev/core/${finalAttrs.version}/herdr-core-linux-x86_64.tar.gz";
    hash = "sha256-guxEBD9olL/bcWuXm4fNpD/X+kawEE57e9k+ZNGpuHc=";
  };

  sourceRoot = ".";

  # 静的リンク (musl) なので patchelf は要らない。
  installPhase = ''
    runHook preInstall

    install -Dm755 herdr-core $out/bin/herdr-core
    ln -s herdr-core $out/bin/hc

    runHook postInstall
  '';

  dontStrip = true;

  meta = {
    description = "Runs programs and coding agents in terminals that stay alive";
    homepage = "https://github.com/herdrdev/herdr-core";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "hc";
  };
})
