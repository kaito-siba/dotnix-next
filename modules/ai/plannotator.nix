{
  # Plannotator: プラン・diff・HTML をブラウザ上で注釈してエージェントに返す
  # ローカルレビュー UI。upstream は curl | bash で ~/.local/bin にバイナリを
  # 置くインストーラ配布なので、GitHub Release のビルド済みバイナリを取り込む。
  #
  # semantic diff 用の sem サイドカー (別リポジトリ) も同梱する。plannotator は
  # PLANNOTATOR_SEM_PATH → ~/.plannotator/vendor/sem/<upstream pin>/sem → PATH
  # の順に探し、PATH 経由で見つけたものは `sem --version` が応答すれば
  # バージョンを問わず採用する (packages/shared/semantic-diff.ts の resolveSem)。
  # よって upstream の pin (PLANNOTATOR_SEM_VERSION) と semVersion がずれても
  # 壊れず、plannotator を上げるときに併せて見直せば十分。
  #
  # 更新手順: 下の 2 コマンドで出る sha256:<hex> を
  #   nix hash convert --hash-algo sha256 --to sri <hex>
  # で SRI に変換して hash を差し替える。
  #   gh release view --repo backnotprop/plannotator --json tagName,assets \
  #     -q '.tagName, (.assets[] | "\(.name) \(.digest)")'
  #   gh release view --repo Ataraxy-Labs/sem --json tagName,assets \
  #     -q '.tagName, (.assets[] | "\(.name) \(.digest)")'
  #
  # エージェント連携の分担:
  #   - Claude Code の hooks (plan review / improve-context) はプラグイン経由。
  #       /plugin marketplace add backnotprop/plannotator
  #       /plugin install plannotator
  #     プラグイン (apps/hook) が持つのは hooks.json だけで skill は入らない。
  #   - skill は upstream の sparse checkout をそのまま symlink する。Claude Code
  #     は apps/skills/claude (`!`plannotator …`` の動的注入 + allowed-tools)、
  #     Codex は apps/skills/core (prose 版) を読むので本文が別物。Codex 側の
  #     共有パスは ~/.agents/skills。
  #   - Codex の Stop hook だけは宣言的に置けない。~/.codex/hooks.json は orca /
  #     herdr が既にフックを書き込んでいる共有ファイルなので、activation で
  #     plannotator のエントリだけを jq マージする。
  #     ~/.codex/config.toml の `[features] hooks = true` は既に有効。
  flake.modules.homeManager.ai =
    { lib, pkgs, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) isLinux system;

      plannotatorVersion = "0.27.14";
      plannotatorAssets = {
        x86_64-linux = {
          file = "plannotator-linux-x64";
          hash = "sha256-ldslSssqmW6w2DKJq7uR384rDd7jeLY3UgXj6CUajbA=";
        };
        aarch64-linux = {
          file = "plannotator-linux-arm64";
          hash = "sha256-XrvW0VEwwmM7+pspUxIFfoJ3lUqY9ALbZesSSzHnCE0=";
        };
        aarch64-darwin = {
          file = "plannotator-darwin-arm64";
          hash = "sha256-Hp9w9FTTkwKPLW/hLaiqq5MbNZH9NBqtNCgP8ZgepNA=";
        };
        x86_64-darwin = {
          file = "plannotator-darwin-x64";
          hash = "sha256-jGyTq+4m6BSvS50ddyDKk7Ez64JLis2YTd2cMUHGFHk=";
        };
      };
      plannotatorAsset =
        plannotatorAssets.${system} or (throw "plannotator: unsupported system ${system}");

      semVersion = "0.24.0";
      # plannotator が対応する 4 プラットフォーム分の asset が揃っているが、
      # upstream が asset を落とした環境でも壊れないよう、asset が無ければ
      # 同梱をスキップする (semantic diff だけが無効になる)。
      semAssets = {
        x86_64-linux = {
          file = "sem-linux-x86_64.tar.gz";
          hash = "sha256-kPMbZ6NRqi7GSSFn01xWNukSi+6cUoUpIZQjwUaDGk4=";
        };
        aarch64-linux = {
          file = "sem-linux-arm64.tar.gz";
          hash = "sha256-LQPRsIzzSiif5yQTKA+5/Of8PZ752jCy6kf7zab3gFA=";
        };
        aarch64-darwin = {
          file = "sem-darwin-arm64.tar.gz";
          hash = "sha256-UBtOWp3ov0jUIvHjfwS+RsqGeoH6WJg0k+k4E2TxqiA=";
        };
        x86_64-darwin = {
          file = "sem-darwin-x86_64.tar.gz";
          hash = "sha256-MAbhvDQjQhNtf0Hk68uC9WqZ37IHv9hoxVDa/uk9iZg=";
        };
      };

      plannotator = pkgs.stdenvNoCC.mkDerivation {
        pname = "plannotator";
        version = plannotatorVersion;

        src = pkgs.fetchurl {
          url = "https://github.com/backnotprop/plannotator/releases/download/v${plannotatorVersion}/${plannotatorAsset.file}";
          inherit (plannotatorAsset) hash;
        };

        dontUnpack = true;
        # Bun の単一実行ファイルは JS バンドルを ELF の末尾に埋め込んでいるので
        # strip すると壊れる。
        dontStrip = true;

        nativeBuildInputs = lib.optionals isLinux [ pkgs.autoPatchelfHook ];

        installPhase = ''
          runHook preInstall
          install -Dm755 $src $out/bin/plannotator
          runHook postInstall
        '';

        meta = {
          description = "Local, browser-based review surface for AI coding agents";
          homepage = "https://github.com/backnotprop/plannotator";
          license = with lib.licenses; [
            mit
            asl20
          ];
          mainProgram = "plannotator";
          platforms = [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
            "x86_64-darwin"
          ];
          sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        };
      };

      # skill の markdown だけが必要。フルの tarball は 53MB あるので
      # sparse checkout で apps/skills のみ取る (install.sh と同じ手口)。
      plannotatorSkills = pkgs.fetchFromGitHub {
        owner = "backnotprop";
        repo = "plannotator";
        rev = "v${plannotatorVersion}";
        sparseCheckout = [ "apps/skills" ];
        hash = "sha256-hy0zBci75drcVSt/TdzSn6QulyW2ZiGahS20oAMfeWg=";
      };

      # Claude Code 用: 3 つは claude 専用本文、リファレンスの plannotator だけ
      # 専用版が無いので core と同じものを共有する。
      claudeSkills = {
        plannotator-review = "${plannotatorSkills}/apps/skills/claude/plannotator-review";
        plannotator-annotate = "${plannotatorSkills}/apps/skills/claude/plannotator-annotate";
        plannotator-last = "${plannotatorSkills}/apps/skills/claude/plannotator-last";
        plannotator = "${plannotatorSkills}/apps/skills/core/plannotator";
      };

      # Codex ほか OpenAI 系エージェントが読む共有パス。
      coreSkills = {
        plannotator-review = "${plannotatorSkills}/apps/skills/core/plannotator-review";
        plannotator-annotate = "${plannotatorSkills}/apps/skills/core/plannotator-annotate";
        plannotator-last = "${plannotatorSkills}/apps/skills/core/plannotator-last";
        plannotator = "${plannotatorSkills}/apps/skills/core/plannotator";
      };

      mkSem =
        asset:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "sem";
          version = semVersion;

          src = pkgs.fetchurl {
            url = "https://github.com/Ataraxy-Labs/sem/releases/download/v${semVersion}/${asset.file}";
            inherit (asset) hash;
          };

          # アーカイブ直下に sem バイナリ 1 個だけが入っている。
          sourceRoot = ".";

          nativeBuildInputs = lib.optionals isLinux [ pkgs.autoPatchelfHook ];
          buildInputs = lib.optionals isLinux [
            pkgs.openssl
            pkgs.zlib
            pkgs.stdenv.cc.cc.lib
          ];

          installPhase = ''
            runHook preInstall
            install -Dm755 sem $out/bin/sem
            runHook postInstall
          '';

          meta = {
            description = "Semantic diff CLI used by plannotator's code review";
            homepage = "https://github.com/Ataraxy-Labs/sem";
            mainProgram = "sem";
            platforms = [
              "x86_64-linux"
              "aarch64-linux"
              "aarch64-darwin"
            ];
            sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
          };
        };
    in
    {
      home.packages = [
        plannotator
      ]
      ++ map mkSem (lib.optional (semAssets ? ${system}) semAssets.${system});

      home.file =
        lib.mapAttrs' (name: src: lib.nameValuePair ".claude/skills/${name}" { source = src; }) claudeSkills
        // lib.mapAttrs' (
          name: src: lib.nameValuePair ".agents/skills/${name}" { source = src; }
        ) coreSkills;

      # Codex は plan mode を持たないので、plannotator は Stop hook として動く。
      # ~/.codex/hooks.json は他ツールと共有しているため上書きせず、plannotator
      # のエントリだけを冪等にマージする (basename が plannotator のものを
      # 「自分の」エントリとみなす upstream の判定に合わせている)。
      home.activation.plannotatorCodexHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        codexHooks="''${CODEX_HOME:-$HOME/.codex}/hooks.json"
        plannotatorBin=${lib.escapeShellArg "${plannotator}/bin/plannotator"}

        if [ ! -e "$codexHooks" ]; then
          $DRY_RUN_CMD mkdir -p "$(dirname "$codexHooks")"
          $DRY_RUN_CMD ${pkgs.jq}/bin/jq -n --arg cmd "$plannotatorBin" \
            '{ hooks: { Stop: [ { hooks: [ { type: "command", command: $cmd, timeout: 345600 } ] } ] } }' \
            > "$codexHooks"
          echo "plannotator: created $codexHooks"
        elif merged=$(${pkgs.jq}/bin/jq --arg cmd "$plannotatorBin" '
          def managed: ((.command // "") | . == "plannotator" or endswith("/plannotator"));
          def entry: { type: "command", command: $cmd, timeout: 345600 };
          .hooks //= {}
          | .hooks.Stop //= []
          | if (.hooks.Stop | map((.hooks // []) | map(managed) | any) | any)
            then .hooks.Stop |= map(
              if ((.hooks // []) | map(managed) | any)
              then .hooks |= map(if managed then entry else . end)
              else . end)
            else .hooks.Stop += [ { hooks: [ entry ] } ]
            end
        ' "$codexHooks"); then
          if [ "$merged" != "$(cat "$codexHooks")" ]; then
            $DRY_RUN_CMD printf '%s\n' "$merged" > "$codexHooks.plannotator-tmp"
            $DRY_RUN_CMD mv "$codexHooks.plannotator-tmp" "$codexHooks"
            echo "plannotator: merged Stop hook into $codexHooks"
          fi
        else
          echo "plannotator: could not parse $codexHooks — Codex Stop hook not configured" >&2
        fi
      '';
    };
}
