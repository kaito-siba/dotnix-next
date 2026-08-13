{
  # Guguru Sans Code (https://github.com/yuru7/guguru-sans-code):
  # Google Sans Code + IBM Plex Sans JP 合成のプログラミングフォント。
  # nixpkgs 未収録のため公式リリースの zip を fetchzip で取り込む。
  #
  # ファミリー名:
  #   Guguru Sans Code / Guguru Sans Code 35 (1:2 / 3:5 幅)
  #   Guguru Sans Code Console (NF) / Console 35(NF) (ターミナル向け)
  flake.modules =
    let
      guguruFonts =
        pkgs:
        let
          version = "0.0.3";

          fetchRelease =
            name: hash:
            pkgs.fetchzip {
              url = "https://github.com/yuru7/guguru-sans-code/releases/download/v${version}/${name}_v${version}.zip";
              inherit hash;
            };

          plain = fetchRelease "GuguruSansCode" "sha256-o12zdEnmXU6dZkgTT9z9sEgGYOMSSdqafEB2mwlt6gE=";
          nf = fetchRelease "GuguruSansCodeNF" "sha256-hmxjOgt6gKTfcfU59IP2mMKHOgql4FBlxz3NBNh3jUA=";
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "guguru-sans-code";
          inherit version;

          srcs = [
            plain
            nf
          ];
          dontUnpack = true;

          installPhase = ''
            runHook preInstall
            mkdir -p $out/share/fonts/truetype
            find ${plain} ${nf} -name '*.ttf' -exec cp {} $out/share/fonts/truetype/ \;
            runHook postInstall
          '';

          meta = {
            description = "Programming font combining Google Sans Code and IBM Plex Sans JP";
            homepage = "https://github.com/yuru7/guguru-sans-code";
            license = pkgs.lib.licenses.ofl;
          };
        };
    in
    {
      darwin.fonts =
        { pkgs, ... }:
        {
          fonts.packages = [ (guguruFonts pkgs) ];
        };

      nixos.fonts =
        { pkgs, ... }:
        {
          fonts.packages = [ (guguruFonts pkgs) ];
        };
    };
}
