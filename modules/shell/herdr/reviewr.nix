{
  # herdr-reviewr: herdr のペインで動くコードレビュー UI。エージェントの diff を
  # 隣で読み、行にコメントを付けてエージェントの入力欄に送り返す。
  #
  # upstream は `herdr plugin install persiyanov/herdr-reviewr` を推すが、これは
  # マニフェストの [[build]] でリリースバイナリを curl する。ここでは代わりに
  #   1. リリースの musl バイナリを固定 hash で取り (完全静的なので patchelf 不要)
  #   2. store 上に plugin root を組み立て
  #   3. activation で `herdr plugin link` に登録する
  # `plugin link` は [[build]] をスキップするので、bin/herdr-reviewr は自分で置く。
  #
  # ソースビルドにしていない理由: rust-version = "1.97" / edition = 2024 を要求し、
  # stable nixpkgs の rustc は 1.95 (unstable が 1.97)。公式が静的 musl を配って
  # いるのでリリース物を取るほうが素直。
  #
  # 更新手順: version を上げ、下のコマンドで出る sha256:<hex> を
  #   nix hash convert --hash-algo sha256 --to sri <hex>
  # で SRI に変換して差し替える (pluginSrc の hash はビルド時のエラーに出る)。
  #   gh release view --repo persiyanov/herdr-reviewr --json tagName,assets \
  #     -q '.tagName, (.assets[] | "\(.name) \(.digest)")'
  flake.modules.homeManager.shell =
    {
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;

      version = "0.36.2";

      assets = {
        x86_64-linux = {
          target = "x86_64-unknown-linux-musl";
          hash = "sha256-P1mWvp+9ie3LlN5MMlZIPkpsopxA+YHhUFVBWQtYKX8=";
        };
        aarch64-linux = {
          target = "aarch64-unknown-linux-musl";
          hash = "sha256-8c3hLNYiSK03XQz2i44WCVAD+ul/I62jQZmmtl3aX/4=";
        };
        aarch64-darwin = {
          target = "aarch64-apple-darwin";
          hash = "sha256-gf1BcymDZ8D1LZaeE7LB7vj1Qx2CUFNJegVs7bjR8mE=";
        };
        x86_64-darwin = {
          target = "x86_64-apple-darwin";
          hash = "sha256-r2vbg4/yvVC3a8NnkxVPt/OzUMP4BFp5LVjkSX8blTA=";
        };
      };
      asset = assets.${system} or (throw "herdr-reviewr: unsupported system ${system}");

      herdr-reviewr = pkgs.stdenvNoCC.mkDerivation {
        pname = "herdr-reviewr";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://github.com/persiyanov/herdr-reviewr/releases/download/v${version}/herdr-reviewr-${asset.target}.tar.gz";
          inherit (asset) hash;
        };

        # アーカイブ直下に herdr-reviewr バイナリ 1 個だけ。
        sourceRoot = ".";

        installPhase = ''
          runHook preInstall
          install -Dm755 herdr-reviewr $out/bin/herdr-reviewr
          runHook postInstall
        '';

        meta = {
          description = "Code review pane for herdr: review agent diffs and send line comments back";
          homepage = "https://github.com/persiyanov/herdr-reviewr";
          license = lib.licenses.mit;
          mainProgram = "herdr-reviewr";
          platforms = builtins.attrNames assets;
          sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        };
      };

      # マニフェストと pane.sh だけが必要なので sparse checkout で取る。
      pluginSrc = pkgs.fetchFromGitHub {
        owner = "persiyanov";
        repo = "herdr-reviewr";
        rev = "v${version}";
        sparseCheckout = [
          "herdr"
          "herdr-plugin.toml"
        ];
        hash = "sha256-sDe4ORMofQhL8ihYQjwqxBIBXTyIrWxIPBTnlUEnZ0o=";
      };

      # HERDR_PLUGIN_ROOT として link する plugin root。
      reviewrPlugin = pkgs.runCommand "herdr-reviewr-plugin-${version}" { } ''
        mkdir -p $out/bin
        cp ${pluginSrc}/herdr-plugin.toml $out/
        cp -r ${pluginSrc}/herdr $out/herdr
        chmod -R u+w $out/herdr

        # herdr は plugin コマンドを最小 PATH で起動するため、pane.sh は自前で
        # PATH を組み立てて jq (設定の読み出し) と git を解決している。upstream の
        # 候補は homebrew / /usr/bin なので NixOS では jq が見つからず、全アクションが
        # "normalized configuration is unreadable" で落ちる。store path を足して直す。
        substituteInPlace $out/herdr/pane.sh \
          --replace-fail \
            'export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:''${PATH:-}"' \
            'export PATH="${
              lib.makeBinPath [
                pkgs.jq
                pkgs.git
              ]
            }:''${PATH:-}"'

        # pane のコマンドは $HERDR_PLUGIN_ROOT/bin/herdr-reviewr を直接 exec する。
        ln -s ${herdr-reviewr}/bin/herdr-reviewr $out/bin/herdr-reviewr
      '';

      herdrPkg = inputs.herdr.packages.${system}.default;
    in
    {
      # plugin ペインとしてだけでなく、単体 TUI (`herdr-reviewr <repo>`) としても使う。
      home.packages = [ herdr-reviewr ];

      # `herdr plugin link` は渡したパスを canonicalize して plugins.json に記録し、
      # マニフェスト (version / actions) ごとキャッシュする。よって store path が
      # 変わる更新のたびに再 link が必要で、安定 symlink を噛ませても回避できない。
      # 再 link は冪等なので、記録済みの plugin_root が現在の store path と
      # 違うときだけ実行する。
      home.activation.herdrReviewrPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        registry="''${XDG_CONFIG_HOME:-$HOME/.config}/herdr/plugins.json"
        want=${lib.escapeShellArg "${reviewrPlugin}"}
        have=""

        if [ -r "$registry" ]; then
          have=$(${pkgs.jq}/bin/jq -r \
            '[.[]? | select(.plugin_id == "persiyanov.reviewr") | .plugin_root] | first // ""' \
            "$registry" 2>/dev/null || true)
        fi

        if [ "$have" != "$want" ]; then
          if $DRY_RUN_CMD ${herdrPkg}/bin/herdr plugin link "$want" > /dev/null; then
            echo "herdr-reviewr: linked $want"
          else
            echo "herdr-reviewr: 'herdr plugin link' failed — link it manually" >&2
          fi
        fi
      '';
    };
}
