{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "sbx";
  # 0.51.0 は 2026-11-03 公開で冷却 7 日を満たしていないが、試用段階なので例外。
  # nixpkgs 未収録のバイナリなので手動 bump (version と hash を書き換える)。
  version = "0.51.0";

  src = fetchurl {
    url = "https://github.com/docker/sbx-releases/releases/download/v${finalAttrs.version}/DockerSandboxes-linux-amd64.tar.gz";
    hash = "sha256-XWBdlN0penlhiKrUCVpKLyI2jI8nDy2sSfLt5FPU0+w=";
  };

  sourceRoot = "docker-sbx";

  # sbx 本体は静的リンク。shim / docklet / mkfs.* / libsailor.so は glibc 向けなので patch する。
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  # sbx は自身の隣の ../libexec から helper を探すので、install.sh と同じ配置にする。
  # GPU shim は suid を付けないと使えない (`sudo <shim> install`) ので同梱だけしておく。
  installPhase = ''
    runHook preInstall

    install -Dm755 sbx $out/bin/sbx

    for f in docker-docklet containerd-shim-nerdbox-v1 containerd-shim-nerdbox-gpu-v1 mkfs.erofs mkfs.ext4; do
      install -Dm755 $f $out/libexec/$f
    done
    install -m644 nerdbox-kernel-* nerdbox-rootfs-*.erofs sailor-rootfs-*.erofs $out/libexec/
    install -Dm755 libsailor.so $out/libexec/lib/libsailor.so

    runHook postInstall
  '';

  dontStrip = true;

  meta = {
    description = "Run AI coding agents in isolated microVM sandboxes";
    homepage = "https://docs.docker.com/ai/sandboxes/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "sbx";
  };
})
