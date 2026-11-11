{
  lib,
  runCommand,
  fetchurl,
  writeShellApplication,
  writeText,
  coreutils,
  fontconfig,
  imagemagick,
  jq,
  # 同梱の layout / mod を写す元の tag。_package.nix の version と揃える。
  appVersion,
}:
let
  # Show パネルに物を置き、注釈を焼き込むコマンド。mod からも端末からも
  # (つまりエージェントからも) 同じ物を呼ぶ。
  show = writeShellApplication {
    name = "show";

    runtimeInputs = [
      coreutils
      fontconfig
      imagemagick
      jq
    ];

    text = builtins.readFile ./show/show.sh;
  };

  # app 同梱の main layout と tabs mod は起動のたびに上書きされ、手を入れられ
  # ない (defaults/AGENTS.md)。Show を足した写しを自分の名前で持つ。写しを
  # repo に置くと bump のたびに写し直しになるので、同じ tag の原本を取ってきて
  # 差分だけ当てる。原本が変わって差分が当たらなくなったら build が落ちる。
  # hash は bump のたびに書き換える。
  upstream =
    path: hash:
    fetchurl {
      url = "https://raw.githubusercontent.com/herdrdev/herdr-app/v${appVersion}/defaults/${path}";
      inherit hash;
    };

  mainLayout = upstream "layouts/main.json" "sha256-tEONr88ao3mw0ItiqXrzezG7Y7n/nlU30YSKjyIb6n8=";
  tabsMod = upstream "mods/tabs/main.js" "sha256-EtTsyJ2/hk1aiJ8kCtrqJVkIEuC+GDW72z5jb+FPUdM=";

  # mod は store のパスを知らないので、呼ぶコマンドを module として渡す。
  env = writeText "herdr-show-env.js" ''
    export const SHOW = "${lib.getExe show}";
  '';
in
# ~/.config/herdr-app にそのまま重ねる木。
runCommand "herdr-app-show"
  {
    nativeBuildInputs = [ jq ];
    passthru = { inherit show; };
  }
  ''
    mkdir -p $out/layouts $out/mods/show $out/mods/show-tabs

    install -m644 ${./show/main.js} $out/mods/show/main.js
    install -m644 ${./show/mod.json} $out/mods/show/mod.json
    install -m644 ${./show/show.svg} $out/mods/show/show.svg
    install -m644 ${./show/send.svg} $out/mods/show/send.svg
    install -m644 ${env} $out/mods/show/env.js

    # layout: 右パネルの stack に show を足し、タブバーを写しに差し替える。
    jq '
      (.. | objects | select(.id? == "tabs") | .content.mod) = "show-tabs"
      | (.. | objects | select(.id? == "panel-body") | .children)
          += [{id: "show", type: "block", content: {mod: "show"}}]
    ' ${mainLayout} > $out/layouts/show.json
    jq -e '
      [.. | objects | select(.id? == "tabs") | .content.mod] == ["show-tabs"]
      and ([.. | objects | select(.id? == "panel-body") | .children[].id] | index("show") != null)
    ' $out/layouts/show.json > /dev/null

    # タブバー: Files / Changes の隣に Show のボタンを足す。開いていたパネル
    # を space ごとに覚える処理にも show を通す。
    install -m644 ${tabsMod} $out/mods/show-tabs/main.js
    substituteInPlace $out/mods/show-tabs/main.js \
      --replace-fail \
        'enabled.includes(stored) ? stored : null' \
        '(stored === "show" || enabled.includes(stored)) ? stored : null' \
      --replace-fail \
        '.when(enabled.includes("changes"), el => el.child(panelButton("changes", "Changes", "mods/changes/changes.svg")))' \
        '.when(enabled.includes("changes"), el => el.child(panelButton("changes", "Changes", "mods/changes/changes.svg"))).child(panelButton("show", "Show", "mods/show/show.svg"))'
    echo '{ "place": "none", "title": "Tabs" }' > $out/mods/show-tabs/mod.json
  ''
