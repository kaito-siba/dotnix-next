# security/

供給網対策の運用部分。

## 方針

| 層 | 対象 | 更新 |
|---|---|---|
| stable | nixpkgs (nixos-26.05)。ほぼ全部 | 週 1 の CI PR、自動 merge |
| 例外 | nixpkgs-unstable から取る keifu / yt-dlp / codex、claude-code | 週 1 の CI PR、冷却 7 日 |
| 直接 input | nixpkgs 以外の flake input。`inputs.nixpkgs.follows` は stable | 同上 |
| バイナリ pin | URL に commit を書いた input (look)、fetchurl の hash 固定 (defi / smoothcsv) | 手で上げる |

## 何が動くか

| workflow | いつ | 何をするか |
|---|---|---|
| `weekly-update` | 土曜 09:00 JST | `nix flake update`。nixpkgs だけの PR は全ホストの評価が通れば自動 merge。それ以外の input の PR は人間が読んで merge |
| `pr-check` | PR ごと | 全ホストが評価できること。flake.lock が動いた PR は変更された input が冷却期間 (7 日) を満たすこと |
| `daily-security` | 毎日 09:30 JST | vulnix (NVD) + OSV + GitHub advisories。結果は Actions の summary と artifact |

全部ビルドなし。`nix derivation show -r` で derivation を列挙するだけなので darwin ホストも Linux runner で評価できる。

## 日々の運用

- **weekly-update の inputs PR**: 本文の lock 差分と closure 差分を読む。冷却チェックが落ちていたら、日付が過ぎるのを待って `pr-check` を再実行するか、CVE 対応なら `security-fastlane` ラベルを付けて通す。
- **daily-security**: 最初の 1 か月は report-only。summary に「New findings」が出たら triage して、
  - 誤検知で恒久的なもの → `vulnix-whitelist.toml`
  - 本物だが今は対応しないもの → `baseline.json` の `keys` に追加 (version が変わると再浮上する)
  - 対応するもの → 手で Issue を立てるか、nixpkgs 側で直っていれば `weekly-update` を `scope=nixpkgs` で手動実行
- **Issue 化を有効にする**: リポジトリ変数 `SECURITY_ISSUES=true`。baseline に無く、7 日以上残った finding だけが「パッケージ + 検出元」単位で Issue になり、消えたら自動 close する。
- **前倒し更新**: `SECURITY_FASTLANE=true` で、vulnix ヒットのパッケージが stable channel HEAD で version が上がっていたら、その日のうちに nixpkgs 更新を dispatch する。

## 初期設定 (一度だけ)

1. Settings > Actions > General で "Allow GitHub Actions to create and approve pull requests" を on。
2. 任意: `BOT_TOKEN` secret (PAT か GitHub App token)。無いと bot が作った PR で `pr-check` が走らない (GITHUB_TOKEN の制限)。
3. `baseline.json` は導入時のスキャン結果を手で triage したもの。

## 手元で動かす

```sh
python3 security/scripts/closure.py /tmp/closure.json
python3 security/scripts/cooling.py flake.lock
nix shell --inputs-from . nixpkgs#vulnix -c \
  python3 security/scripts/scan.py --closure /tmp/closure.json --lock flake.lock --out /tmp/results.json
```

## 限界

- vulnix は名前と version の CPE 照合なので誤検知が多い。whitelist と baseline で吸収する前提。
- GitHub advisories は「存在する」ことしか見ない。affected range の判定は人間。
- upstream が advisory も CVE も出さないケースは拾えない。冷却期間が唯一の防御。
