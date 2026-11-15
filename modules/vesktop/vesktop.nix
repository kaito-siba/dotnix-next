{
  flake.modules.homeManager.vesktop =
    { pkgs, ... }:
    let
      # nixpkgs の vencord に my-plugins (userplugins) を同梱する
      vencordWithPlugins = pkgs.vencord.overrideAttrs (old: {
        # pnpm install 後・ビルド前に userplugins を src へ配置
        # 依存関係は増えないため pnpmDeps のハッシュには影響しない
        preBuild = (old.preBuild or "") + ''
          mkdir -p src/userplugins
          cp -r ${./userplugins}/. src/userplugins/
          # LICENSE はリポジトリ用。Vencord は userplugins 内の全ファイルを
          # プラグインとしてコンパイルするため、ビルド対象からは除外する
          rm -f src/userplugins/LICENSE
        '';
      });
    in
    {
      programs.vesktop = {
        enable = true;
        # HM モジュールが package に対して withSystemVencord = vencord.useSystem を
        # 再適用するため、ここで true にしないと stock に戻される
        vencord.useSystem = true;
        # 差し込む vencord 本体（プラグイン同梱版）を指定。withSystemVencord は
        # モジュール側が useSystem から付与するので override しない
        package = pkgs.vesktop.override { vencord = vencordWithPlugins; };
      };
    };
}
