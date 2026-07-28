{
  # OpenAI Codex CLI, taken from the upstream musl release binary, plus its
  # home directory config and bubblewrap for sandboxed runs.
  flake.modules.homeManager.ai =
    { pkgs, ... }:
    let
      codex-rs = pkgs.stdenv.mkDerivation rec {
        pname = "codex";
        version = "0.144.1";

        src = pkgs.fetchurl {
          url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-x86_64-unknown-linux-musl.tar.gz";
          sha256 = "sha256-hAka4gxl/MfUEg25fRvVfX/435x2Cft4HHjC671PWig=";
        };

        dontUnpack = true;

        installPhase = ''
          mkdir -p $out/bin
          tar -xzf $src -C $out/bin
          mv $out/bin/codex-x86_64-unknown-linux-musl $out/bin/codex
          chmod +x $out/bin/codex
        '';
      };
    in
    {
      home.packages = [
        codex-rs
        pkgs.bubblewrap # for sandboxing codex
      ];

      home.file.".codex/" = {
        source = ./codex-home;
        recursive = true;
      };
    };
}
