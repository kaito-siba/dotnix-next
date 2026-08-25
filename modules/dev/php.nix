{
  nixpkgs.allowedUnfreePackages = [ "intelephense" ];

  flake.modules.homeManager.dev =
    { pkgs, ... }:
    let
      # intelephense はプロジェクトのインデックスを全てメモリに載せるため、
      # node の old-space デフォルト上限 (~4GB) だと大きなリポジトリで OOM する。
      # 本体は unfree でローカルビルドになるので、overrideAttrs による
      # 再ビルドを避けて symlinkJoin でラップするだけにしている。
      intelephense = pkgs.symlinkJoin {
        name = "intelephense-wrapped";
        paths = [ pkgs.intelephense ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/intelephense \
            --set NODE_OPTIONS "--max-old-space-size=8192"
        '';
      };
    in
    {
      home.packages = with pkgs; [
        intelephense
      ];
    };
}
