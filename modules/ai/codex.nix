{
  # OpenAI Codex CLI, plus its home directory config and bubblewrap for
  # sandboxed runs.
  #
  # 以前は upstream の musl リリースバイナリを手で pin していたが、nixpkgs
  # に収録されたのでそちらに寄せた。hash 更新が要らず、cache.nixos.org に
  # ビルド済みが載っていて、codex 本体に加えて codex-code-mode-host と
  # シェル補完まで入る。stable (26.05) は追従が遅いので unstable から取る。
  flake.modules.homeManager.ai =
    {
      lib,
      pkgs,
      pkgs-unstable,
      ...
    }:
    {
      home.packages = [
        pkgs-unstable.codex
      ]
      # bubblewrap は Linux 専用。darwin では codex が Seatbelt を使う。
      ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.bubblewrap;

      home.file.".codex/" = {
        source = ./codex-home;
        recursive = true;
      };
    };
}
