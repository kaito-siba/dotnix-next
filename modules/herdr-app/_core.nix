{
  lib,
  stdenv,
  fetchurl,
}:
let
  # release の target 名と、その tarball の hash。hash は
  # https://releases.herdr.dev/core/<version>/manifest.json の sha256。
  sources = {
    x86_64-linux = {
      target = "linux-x86_64";
      hash = "sha256-rGuGiQxFGjdYRiCqpDi3G8DQvUMKLnwdfglfBSxBTnQ=";
    };
    aarch64-darwin = {
      target = "macos-aarch64";
      hash = "sha256-5YmF0/726QnzPTxaRCbkiYyBVkpVfUY2WRzsnjoGryY=";
    };
  };
  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "herdr-core: ${stdenv.hostPlatform.system} 向けの release を入れていない");
in
stdenv.mkDerivation (
  finalAttrs:
  {
    pname = "herdr-core";
    # nixpkgs 未収録のバイナリなので手動 bump (version と hash を書き換える)。
    # herdr-app の distribution/core-version が要求する最低 version を下回らせない。
    version = "0.1.20";

    src = fetchurl {
      url = "https://releases.herdr.dev/core/${finalAttrs.version}/herdr-core-${source.target}.tar.gz";
      inherit (source) hash;
    };

    sourceRoot = ".";

    # linux 版は静的リンク (musl) なので patchelf は要らない。macOS 版は署名済み
    # なので、どちらも中身には触らずに置く。
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
      platforms = builtins.attrNames sources;
      mainProgram = "hc";
    };
  }
  # 署名を壊さないよう、macOS では fixup をさせない。
  // lib.optionalAttrs stdenv.hostPlatform.isDarwin { dontFixup = true; }
)
