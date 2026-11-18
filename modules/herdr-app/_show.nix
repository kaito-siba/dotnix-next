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
  # inbox (./mods/inbox) が Slack の依頼と standup の下書きを読む、work-digest の
  # API の URL。無ければ null。
  workDigestUrl ? null,
  # inbox が commitment (自分への約束) を読み書きする、aw-secretary の API の URL。
  # 無ければ null。
  commitmentsUrl ? null,
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

  # mod は nix の設定を知らないので、module として渡す。inbox と、その中身を
  # 取りに行く show-tabs の両方に置く。
  inboxEnv = writeText "herdr-inbox-env.js" ''
    export const WORK_DIGEST = ${builtins.toJSON workDigestUrl};
    export const COMMITMENTS = ${builtins.toJSON commitmentsUrl};
  '';
in
# ~/.config/herdr-app にそのまま重ねる木。
runCommand "herdr-app-show"
  {
    nativeBuildInputs = [ jq ];
    passthru = { inherit show; };
  }
  ''
    mkdir -p $out/layouts $out/mods/show $out/mods/inbox $out/mods/explorer $out/mods/sandbox $out/mods/show-tabs $out/mods/backdrop-agents $out/mods/bare-chrome $out/mods/titled-pane

    install -m644 ${./show/main.js} $out/mods/show/main.js
    install -m644 ${./show/mod.json} $out/mods/show/mod.json
    install -m644 ${./show/show.svg} $out/mods/show/show.svg
    install -m644 ${./show/send.svg} $out/mods/show/send.svg
    install -m644 ${env} $out/mods/show/env.js

    # Inbox: 自分の手を待っている物を並べるモーダル。mod が import する module
    # (feed.js と asks.js と secretary.js と commitments.js と env.js) は link では
    # 置けない: app は mod の folder の外へ辿り着く import を読まない。なので mod
    # ごと、コピーされるこの木に入れる。
    install -m644 ${./mods/inbox/main.js} $out/mods/inbox/main.js
    install -m644 ${./mods/inbox/feed.js} $out/mods/inbox/feed.js
    install -m644 ${./mods/inbox/asks.js} $out/mods/inbox/asks.js
    install -m644 ${./mods/inbox/secretary.js} $out/mods/inbox/secretary.js
    install -m644 ${./mods/inbox/commitments.js} $out/mods/inbox/commitments.js
    install -m644 ${./mods/inbox/mod.json} $out/mods/inbox/mod.json
    install -m644 ${./mods/inbox/inbox.svg} $out/mods/inbox/inbox.svg
    install -m644 ${inboxEnv} $out/mods/inbox/env.js

    # Files: focus している pane の folder から file を辿る dialog (explorer) と、
    # sbx の sandbox を見る dialog (sandbox)。file を辿る所 (browser.js) は同じ物
    # を使う。import する module は link では置けないので、こちらも mod ごと入れる。
    install -m644 ${./mods/explorer/main.js} $out/mods/explorer/main.js
    install -m644 ${./mods/explorer/browser.js} $out/mods/explorer/browser.js
    install -m644 ${./mods/explorer/mod.json} $out/mods/explorer/mod.json
    install -m644 ${./mods/sandbox/main.js} $out/mods/sandbox/main.js
    install -m644 ${./mods/explorer/browser.js} $out/mods/sandbox/browser.js
    install -m644 ${./mods/sandbox/mod.json} $out/mods/sandbox/mod.json

    # layout: 右パネルの stack から files を外して (explorer で見る) show と tasks を足し、タブバーと Agents の一覧と sidebar
    # の頭と pane の header を写しに差し替える。sidebar の足 (Settings と Add machine) は外す:
    # どちらも key と palette から開ける。sidebar の spaces の一覧も外す: space は
    # navigator (./mods/navigator) で移る。
    jq '
      (.. | objects | select(.id? == "tabs") | .content.mod) = "show-tabs"
      | (.. | objects | select(.id? == "agents") | .content.mod) = "backdrop-agents"
      | (.. | objects | select(.id? == "brand") | .content.mod) = "bare-chrome"
      | (.. | objects | select(.id? == "main") | .content.pane.header.content.mod) = "titled-pane"
      | (.. | objects | select(.id? == "sidebar") | .children) |= map(select(.id != "sidebar-footer"))
      | (.. | objects | select(.id? == "sidebar-lists") | .children) |= map(select(.id != "spaces"))
      | (.. | objects | select(.id? == "panel-body"))
          |= (.active = "changes" | .children |= map(select(.id != "files")) + (["show", "tasks"] | map({id: ., type: "block", content: {mod: .}})))
    ' ${mainLayout} > $out/layouts/lycoreco.json
    jq -e '
      [.. | objects | select(.id? == "tabs") | .content.mod] == ["show-tabs"]
      and [.. | objects | select(.id? == "agents") | .content.mod] == ["backdrop-agents"]
      and [.. | objects | select(.id? == "brand") | .content.mod] == ["bare-chrome"]
      and [.. | objects | select(.id? == "main") | .content.pane.header.content.mod] == ["titled-pane"]
      and ([.. | objects | select(.id? == "sidebar-footer")] | length == 0)
      and [.. | objects | select(.id? == "sidebar-lists") | .children[].id] == ["agents"]
      and [.. | objects | select(.id? == "panel-body") | .children[].id] == ["changes", "show", "tasks"]
      and [.. | objects | select(.id? == "panel-body") | .active] == ["changes"]
    ' $out/layouts/lycoreco.json > /dev/null

    # sidebar の頭: logo と app の名前の代わりに、今の space の名前を出す。spaces の
    # 一覧を外したので、他に出る所が無い。
    { echo 'import { spaces } from "herdr";'; cat ${chromeMod}; } > $out/mods/bare-chrome/main.js
    substituteInPlace $out/mods/bare-chrome/main.js \
      --replace-fail \
        'h_flex().flex_1().gap(8).items_center().child(image("frame/welcome/herdr.png").size(20).rounded(5)).child(div().font_semibold().text_color(t.foreground).child("Herdr"))' \
        'div().flex_1().min_w(0).truncate().font_semibold().text_color(t.foreground).child(spaces().find(s => s.active)?.name ?? "")'
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
    # 返事を待っている agent の行の下には、質問の抜粋を出す (./mods/inbox/asks.js)。
    # 抜粋は Inbox と分け合う。画面を読みに行くのは、いつも出ているこちら。
    { echo 'import { backdrop } from "./backdrop.js";'; echo 'import { readAsks, withAsk } from "./asks.js";'; cat ${agentsMod}; } > $out/mods/backdrop-agents/main.js
    substituteInPlace $out/mods/backdrop-agents/main.js \
      --replace-fail \
        '.bg(t.chrome)' \
        '.bg(t.chrome).relative().overflow_hidden().id("agents-backdrop").on_size_change((size, cx) => { this.area = size; cx.notify(); }).when(!collapsed, (el) => el.child(backdrop(this.area)))' \
      --replace-fail \
        'this.track(list, now);' \
        'this.track(list, now); readAsks(cx, list);' \
      --replace-fail \
        'const r = row(a, i, subs);' \
        'const r = withAsk(row(a, i, subs), a, t, collapsed);'
    install -m644 ${./backdrop/backdrop.js} $out/mods/backdrop-agents/backdrop.js
    install -m644 ${./mods/inbox/asks.js} $out/mods/backdrop-agents/asks.js
    echo '{ "place": "none", "title": "Agents" }' > $out/mods/backdrop-agents/mod.json

    # タブバー: Files のボタンを外し、Changes の隣に Show と Tasks のボタンを足す。
    # 開いていたパネルを space ごとに覚える処理にもそれらを通す。その隣に Inbox を開く
    # ボタンも足す。Inbox の中身を数分おきに取りに行くのもここ (./mods/inbox/feed.js):
    # モーダルは開いている間しか生きていないので、いつも出ているタブバーに持たせる。
    { echo 'import { start as startInbox, button as inboxButton } from "./inbox.js";'; cat ${tabsMod}; } > $out/mods/show-tabs/main.js
    install -m644 ${./mods/inbox/feed.js} $out/mods/show-tabs/inbox.js
    install -m644 ${inboxEnv} $out/mods/show-tabs/env.js
    substituteInPlace $out/mods/show-tabs/main.js \
      --replace-fail \
        'init() {' \
        'init(_props, cx) { startInbox(cx);' \
      --replace-fail \
        'const enabled = shared("workspace.panels") ?? ["files", "changes"];' \
        'const enabled = (shared("workspace.panels") ?? ["changes"]).filter(p => p !== "files");' \
      --replace-fail \
        'enabled.includes(stored) ? stored : null' \
        '(["show", "tasks"].includes(stored) || enabled.includes(stored)) ? stored : null' \
      --replace-fail \
        '.when(enabled.includes("changes"), el => el.child(panelButton("changes", "Changes", "mods/changes/changes.svg")))' \
        '.when(enabled.includes("changes"), el => el.child(panelButton("changes", "Changes", "mods/changes/changes.svg"))).child(panelButton("show", "Show", "mods/show/show.svg")).child(panelButton("tasks", "Tasks", "mods/tasks/tasks.svg")).child(inboxButton(t))'
    echo '{ "place": "none", "title": "Tabs" }' > $out/mods/show-tabs/mod.json
  ''
