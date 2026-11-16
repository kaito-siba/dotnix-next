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

  # app 同梱の layout と mod は起動のたびに上書きされ、手を入れられない
  # (defaults/AGENTS.md)。手を入れた写しを自分の名前で持つ: main layout の写しが
  # lycoreco、tabs と agents と workspace-chrome と pane の写しが show-tabs と
  # backdrop-agents と bare-chrome と titled-pane。写しを
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
  tabsMod = upstream "mods/tabs/main.js" "sha256-8IDeCL2xjkndsDnqD/GGupxlkf4kKyhbgYSnk+GQ6o4=";
  chromeMod = upstream "mods/workspace-chrome/main.js" "sha256-pNHLMATo+d1KSmnYHMl1cIBxFLlfe9hRZhlXRkUtJtc=";
  paneMod = upstream "mods/pane/main.js" "sha256-m7kCjfBCga2IYWXsDrn8CorG763zmrxNaqCv0TcIecc=";
  agentsMod = upstream "mods/agents/main.js" "sha256-PvcUu/GH+BxPu5GUn0+iuS8NztosUsm8Aeq+xfPX4MQ=";

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
    mkdir -p $out/layouts $out/mods/show $out/mods/show-tabs $out/mods/backdrop-agents $out/mods/bare-chrome $out/mods/titled-pane

    install -m644 ${./show/main.js} $out/mods/show/main.js
    install -m644 ${./show/mod.json} $out/mods/show/mod.json
    install -m644 ${./show/show.svg} $out/mods/show/show.svg
    install -m644 ${./show/send.svg} $out/mods/show/send.svg
    install -m644 ${env} $out/mods/show/env.js

    # layout: 右パネルの stack に show を足し、タブバーと Agents の一覧と sidebar
    # の頭と pane の header を写しに差し替える。sidebar の足 (Settings と Add machine) は外す:
    # どちらも key と palette から開ける。
    jq '
      (.. | objects | select(.id? == "tabs") | .content.mod) = "show-tabs"
      | (.. | objects | select(.id? == "agents") | .content.mod) = "backdrop-agents"
      | (.. | objects | select(.id? == "brand") | .content.mod) = "bare-chrome"
      | (.. | objects | select(.id? == "main") | .content.pane.header.content.mod) = "titled-pane"
      | (.. | objects | select(.id? == "sidebar") | .children) |= map(select(.id != "sidebar-footer"))
      | (.. | objects | select(.id? == "panel-body") | .children)
          += [{id: "show", type: "block", content: {mod: "show"}}]
    ' ${mainLayout} > $out/layouts/lycoreco.json
    jq -e '
      [.. | objects | select(.id? == "tabs") | .content.mod] == ["show-tabs"]
      and [.. | objects | select(.id? == "agents") | .content.mod] == ["backdrop-agents"]
      and [.. | objects | select(.id? == "brand") | .content.mod] == ["bare-chrome"]
      and [.. | objects | select(.id? == "main") | .content.pane.header.content.mod] == ["titled-pane"]
      and ([.. | objects | select(.id? == "sidebar-footer")] | length == 0)
      and ([.. | objects | select(.id? == "panel-body") | .children[].id] | index("show") != null)
    ' $out/layouts/lycoreco.json > /dev/null

    # sidebar の頭: logo と app の名前を出さない。場所は空けたままにして、検索と
    # sidebar を畳むボタンを右に寄せておく。
    install -m644 ${chromeMod} $out/mods/bare-chrome/main.js
    substituteInPlace $out/mods/bare-chrome/main.js \
      --replace-fail \
        'h_flex().flex_1().gap(8).items_center().child(image("frame/welcome/herdr.png").size(20).rounded(5)).child(div().font_semibold().text_color(t.foreground).child("Herdr"))' \
        'div().flex_1()'
    echo '{ "place": "none", "title": "Sidebar header" }' > $out/mods/bare-chrome/mod.json

    # pane の header: agent の pane は、program の名前 ("Claude Code") ではなく
    # agent が付けた端末の title で呼ぶ。Claude Code は session の名前を title に
    # する。前に付く状態の印は落とす (agents mod の clean と同じ)。title が無い間
    # は program の名前のまま。
    install -m644 ${paneMod} $out/mods/titled-pane/main.js
    substituteInPlace $out/mods/titled-pane/main.js \
      --replace-fail \
        'const name = ((p.program?.agent' \
        'const name = (p.program?.agent && (p.title ?? "").replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}]+/u, "").trim()) || ((p.program?.agent'
    echo '{ "place": "none", "title": "Pane header" }' > $out/mods/titled-pane/mod.json

    # Agents の一覧: 根に絵を敷く (./backdrop/backdrop.js)。絵の大きさを決める
    # のに根の大きさが要るので、それも取る。sidebar を畳んでいる間は敷かない。
    { echo 'import { backdrop } from "./backdrop.js";'; cat ${agentsMod}; } > $out/mods/backdrop-agents/main.js
    substituteInPlace $out/mods/backdrop-agents/main.js \
      --replace-fail \
        '.bg(t.chrome)' \
        '.bg(t.chrome).relative().overflow_hidden().id("agents-backdrop").on_size_change((size, cx) => { this.area = size; cx.notify(); }).when(!collapsed, (el) => el.child(backdrop(this.area)))'
    install -m644 ${./backdrop/backdrop.js} $out/mods/backdrop-agents/backdrop.js
    echo '{ "place": "none", "title": "Agents" }' > $out/mods/backdrop-agents/mod.json

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
