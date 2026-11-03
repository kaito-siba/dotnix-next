# security/

サプライチェーン対策の運用部分。

## 方針

| 層 | 対象 | 更新 |
|---|---|---|
| stable | nixpkgs (nixos-26.05)。ほぼ全部 | 週 1 の CI PR、自動 merge |
| 例外 | nixpkgs-unstable から取るもの。`grep -rl pkgs-unstable modules` と、flake.nix で `follows = "nixpkgs-unstable"` の input | 週 1 の CI PR、冷却 7 日 |
| 直接 input | nixpkgs 以外の flake input。`inputs.nixpkgs.follows` は stable | 同上 |
| バイナリ pin | flake.nix の URL に commit を書いた input と、modules 内で fetchurl の hash を固定しているもの | 手で上げる |

## 何が動くか

| workflow | いつ | 何をするか |
|---|---|---|
| `weekly-update` | 土曜 09:00 JST | `nix flake update`。nixpkgs だけの PR は pr-check が通れば自動 merge (`--auto`)。それ以外の input の PR は人間が読んで merge |
| `pr-check` | PR ごと | 全ホストが評価できること。flake.lock が動いた PR は変更された input が冷却期間 (7 日) を満たすこと |
| `daily-security` | 毎日 09:30 JST | vulnix (NVD) + OSV + GitHub advisories。結果は Actions の summary と artifact |

ホストの評価はビルドなし。`nix derivation show -r` で derivation を列挙するだけなので darwin ホストも Linux runner で評価でき、import-from-derivation は禁止してある (`nix develop .#security` だけは vulnix と cvss の devShell を実体化する)。

## 日々の運用

- **weekly-update の inputs PR**: 本文の lock 差分 (推移依存も含む) と closure 差分を読む。本文は 60 KB で打ち切られるので、長いときは artifact の完全版を見る。冷却チェックが落ちていたら、日付が過ぎるのを待って `pr-check` を再実行するか、CVE 対応なら `security-fastlane` ラベルを付ける (ラベルの付け外しで pr-check が走り直す)。
- **daily-security**: 最初の 1 か月は report-only。summary に「New findings」が出たら triage して、
  - 誤検知で恒久的なもの → `vulnix-whitelist.toml`
  - 本物だが今は対応しないもの → `baseline.json` の `keys` に ID 単位で追加 (`vulnix:openssl:3.6.3:CVE-…` の形。version が変わると再浮上する)
  - 対応するもの → 手で Issue を立てるか、nixpkgs 側で直っていれば `weekly-update` を `scope=nixpkgs` で手動実行
- **Issue 化を有効にする**: リポジトリ変数 `SECURITY_ISSUES=true`。新規かどうかは CVE / GHSA などの ID 単位で判定し、baseline に無い ID が完全な run で続けて検出されたら (`MAL-*` は即日、深刻度 9 以上は 2 日連続、それ以外は 7 日。週次更新で直るものを待つための猶予で、`config.toml` で変えられる)、その ID を持つ「パッケージ + version + 検出元」単位で Issue になる。open 済みの Issue に後から別の ID が増えたら本文を更新してコメントする。Issue は baseline に無い ID がその日に検出されている限り維持され、無くなったら close。途中で検出が途切れると 7 日は数え直し。スキャナが 1 つでも失敗した run は「不完全」として記録だけ残し、Issue の open / close も fastlane の dispatch もしない。
- **前倒し更新**: `SECURITY_FASTLANE=true` で、vulnix ヒットのパッケージが stable channel HEAD で version が上がっていたら、その日のうちに nixpkgs 更新を dispatch する。

## 初期設定 (一度だけ)

1. Settings > Actions > General で "Allow GitHub Actions to create and approve pull requests" を on。
2. bot 用の GitHub App。GITHUB_TOKEN で作った PR の `pr-check` は人間が run を承認するまで走らず、master は pr-check 必須なので、無いと weekly-update の自動 merge が進まない。自分名義の App (Settings > Developer settings > GitHub Apps) に権限 Contents: write、Pull requests: write (Metadata: read は自動) を付けてこのリポジトリに install し、App ID を `BOT_APP_ID`、秘密鍵 (.pem の中身) を `BOT_APP_PRIVATE_KEY` として repository secret に置く。秘密鍵に期限は無い。App の名前は後から変えても secret はそのまま。
3. master の ruleset (設定済み): PR 必須 (承認 0)、`eval` と `cooling` の status check 必須、force push と削除禁止、bypass なし。緊急で直接 push したいときは ruleset を一時的に disabled にする。
4. `baseline.json` は 2026-11-03 の完全な run の検出結果を ID 単位で triage したもの。値が理由で、先頭の語で分類している (ビルド時のみ / 本物・stable 未修正 / nixpkgs-llama 由来 / 本物・未対応 / 通知のみ / 対象外 / 修正済み)。同名の別製品などの誤検知は `vulnix-whitelist.toml` に移した。「ビルド時のみ」は radiata の実行時 closure で判定したもので、他ホストの実行時は未確認。深刻度 9 以上はビルド時のみでも理由付きで残している。

## 手元で動かす

```sh
python3 security/scripts/closure.py /tmp/closure.json
python3 security/scripts/cooling.py flake.lock
nix develop .#security -c \
  python3 security/scripts/scan.py --closure /tmp/closure.json --lock flake.lock --out /tmp/results.json
```

## NVD の時間帯

NVD のフィードは `modified` / `recent` が 2 時間ごと、年次が 1 日 1 回 08:00 UTC 頃に再生成され、再生成の前後は 404 を返す。vulnix はキャッシュが 2 時間〜7 日の古さだと `modified` だけを取りに行くので、CI ではキャッシュを持たず毎回年次フィードを取り直す (22:17 UTC 実行なので年次の再生成とは重ならない)。それでも失敗したときは 5 分おきに 3 回まで試し、駄目なら vulnix 抜きで続行する。

## 限界

- 冷却期間は lock の `lastModified` (upstream の commit 時刻) を見るだけで、公開からの経過を証明するものではない。公開直後の汚染版を拾わないための遅延であって、lock を書き換えられる相手には効かない。
- vulnix は名前と version の CPE 照合なので誤検知が多い。whitelist と baseline で吸収する前提。直近 5 年分の NVD しか読まないので、それより古い CVE は見ない。
- GitHub advisories は「存在する」ことしか見ない。affected range の判定は人間。
- severity は出所つきで出す (nvd / cvss3 / cvss4 / label / none)。label は CVSS ベクトルが無いときの代表値で、PYSEC 単独のレコードなどは none になる。
- upstream が advisory も CVE も出さないケースは拾えない。冷却期間が唯一の防御。
