# templates/

プロジェクト用の devShell テンプレート。toolchain はリポジトリごとに pin し、home profile には LSP とフォーマッタだけを残す方針 (modules/dev/*.nix のコメント参照)。

## 自分のリポジトリ

```sh
nix flake init -t github:kaito-siba/dotnix-next#node   # node / rust / python / react-native
direnv allow
```

flake.nix と .envrc を commit する。nixpkgs は nixos-26.05 をリポジトリ側で pin するので、dotnix-next の lock が動いてもプロジェクトは動かない。

## チームのリポジトリ (flake.nix を置けない)

dotnix-next 側の `devShells` を使う。`.envrc` だけ作り、`.git/info/exclude` に入れて自分だけ無視する。

```sh
echo 'use flake ~/repos/github.com/kaito-siba/dotnix-next#node' > .envrc
echo .envrc >> .git/info/exclude
direnv allow
```

mise はチームの task runner のまま触らない。toolchain だけ nix から供給する。

## 注意

`direnv allow` はそのリポジトリの flake を評価して input を fetch する。他人のリポジトリでは中身を読んでから allow すること。
