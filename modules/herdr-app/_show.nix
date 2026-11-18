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
  python3,
  # 同梱の layout / mod を写す元の tag。_package.nix の version と揃える。
  appVersion,
  # inbox (./mods/inbox) が Slack の依頼と commitment (自分への約束) を読み書き
  # する、aw-secretary の API の URL。無ければ null。
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
  # lycoreco、tabs と workspace-chrome と pane の写しが show-tabs と bare-chrome と
  # titled-pane。agents は継承して cheki-agents にする (下の組み立て)。写しを
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

  # 左バーの Agents の一覧 (./mods/cheki-agents) の丸い字、M PLUS Rounded 1c。
  # 2026-11-12 の版 (v1.060) は冷ます日数に満たないので、その前の commit に留める。
  roundedFonts =
    lib.mapAttrsToList
      (
        weight: hash:
        fetchurl {
          url = "https://raw.githubusercontent.com/google/fonts/84efd8ad78c3710ad14bd909e3bc407151885628/ofl/mplusrounded1c/MPLUSRounded1c-${weight}.ttf";
          inherit hash;
        }
      )
      {
        Medium = "sha256-rf3htrrlhxnE4BRGEqlCMucvxcplXEciFl/ojQZSGnA=";
        Bold = "sha256-w1hjBYTo4tj71hIdD0aTJV/+9tHm1PNEH9blqWOhH54=";
        ExtraBold = "sha256-jnwVkB3Kh/FFGzVt2llPfQkrolKl3MR9p0UjokJJPDY=";
      };

  # チェキの下の縁の字を、傾けた svg にする (./mods/cheki-agents/memo.py)。
  memoPython = python3.withPackages (ps: [ ps.fonttools ]);

  # mod は store のパスを知らないので、呼ぶコマンドを module として渡す。
  env = writeText "herdr-show-env.js" ''
    export const SHOW = "${lib.getExe show}";
  '';

  # mod は nix の設定を知らないので、module として渡す。inbox と、その中身を
  # 取りに行く show-tabs の両方に置く。
  inboxEnv = writeText "herdr-inbox-env.js" ''
    export const COMMITMENTS = ${builtins.toJSON commitmentsUrl};
  '';
in
# ~/.config/herdr-app にそのまま重ねる木。
runCommand "herdr-app-show"
  {
    nativeBuildInputs = [
      jq
      memoPython
    ];
    passthru = { inherit show; };
  }
  ''
    mkdir -p $out/layouts $out/mods/show $out/mods/inbox $out/mods/explorer $out/mods/sandbox $out/mods/show-tabs $out/mods/cheki-agents $out/mods/bare-chrome $out/mods/titled-pane

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

    # agent が今居る folder を task-notes に訊く所 (./task-notes/where.js)。link で置く
    # mod (./herdr-app.nix) もこれを import するので、その folder にもこの木からコピーする。
    for mod in explorer lazygit pr scratchpad tasks; do
      install -Dm644 ${./task-notes/where.js} $out/mods/$mod/where.js
    done

    # layout: 右パネルの stack から files を外して (explorer で見る) show と tasks を足し、タブバーと Agents の一覧と sidebar
    # の頭と pane の header を写しに差し替える。sidebar の足 (Settings と Add machine) は外す:
    # どちらも key と palette から開ける。sidebar の spaces の一覧も外す: space は
    # navigator (./mods/navigator) で移る。
    jq '
      (.. | objects | select(.id? == "tabs") | .content.mod) = "show-tabs"
      | (.. | objects | select(.id? == "agents") | .content.mod) = "cheki-agents"
      | (.. | objects | select(.id? == "brand") | .content.mod) = "bare-chrome"
      | (.. | objects | select(.id? == "main") | .content.pane.header.content.mod) = "titled-pane"
      | (.. | objects | select(.id? == "sidebar") | .children) |= map(select(.id != "sidebar-footer"))
      | (.. | objects | select(.id? == "sidebar-lists") | .children) |= map(select(.id != "spaces"))
      | (.. | objects | select(.id? == "panel-body"))
          |= (.active = "changes" | .children |= map(select(.id != "files")) + (["show", "tasks"] | map({id: ., type: "block", content: {mod: .}})))
    ' ${mainLayout} > $out/layouts/lycoreco.json
    jq -e '
      [.. | objects | select(.id? == "tabs") | .content.mod] == ["show-tabs"]
      and [.. | objects | select(.id? == "agents") | .content.mod] == ["cheki-agents"]
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

    # Agents の一覧 (./mods/cheki-agents): 同梱の agents mod を継承して、広い時の
    # 見た目だけを描き直す。原本は手を入れずに upstream.js として置き、継承する
    # 側が使う関数を export で足す。原本でそれらの名前が変わったら build を落とす。
    # 返事を待っている agent の質問の抜粋 (./mods/inbox/asks.js) は Inbox と分け
    # 合う。画面を読みに行くのは、いつも出ているこちら。
    install -m644 ${agentsMod} $out/mods/cheki-agents/upstream.js
    for decl in 'const narrow = ' 'function title(' 'function leadPanes(' 'const kidStatus = ' 'const RANK = ' 'const sortOf = ' \
      '  track(list, now) {' '  migratePins(all) {' '  since(a) {' '  rank(a) {' '  tree(all, addr, lead = []) {' '  subRow(t, s, shown, compact) {' 'this.folded = new Set();'; do
      grep -qF "$decl" $out/mods/cheki-agents/upstream.js \
        || { echo "agents mod の原本に '$decl' が無い: ./mods/cheki-agents/main.js を合わせる" >&2; exit 1; }
    done
    echo 'export { narrow, title, leadPanes, kidStatus, RANK, sortOf };' >> $out/mods/cheki-agents/upstream.js
    install -m644 ${./mods/cheki-agents/main.js} $out/mods/cheki-agents/main.js
    install -m644 ${./mods/cheki-agents/phone.svg} $out/mods/cheki-agents/phone.svg
    install -m644 ${./mods/cheki-agents/zzz.svg} $out/mods/cheki-agents/zzz.svg
    install -m644 ${./mods/cheki-agents/dots.svg} $out/mods/cheki-agents/dots.svg
    # 色と字と状態の印 (./mods/cheki-agents/lycoreco.js) は、右パネルの Tasks と分け合う。
    # Tasks は link で置く mod (./herdr-app.nix) なので、その folder にもこの木からコピーする。
    install -m644 ${./mods/cheki-agents/lycoreco.js} $out/mods/cheki-agents/lycoreco.js
    install -Dm644 ${./mods/cheki-agents/lycoreco.js} $out/mods/tasks/lycoreco.js
    install -m644 ${./mods/inbox/asks.js} $out/mods/cheki-agents/asks.js
    # 丸い字。app は mod の fonts から読むので、system には入れない。
    ${lib.concatMapStringsSep "\n" (
      font: "install -Dm644 ${font} $out/mods/cheki-agents/fonts/${font.name}"
    ) roundedFonts}
    # この版の Bold だけ family の名前が "Rounded Mplus 1c Bold" で、Medium と ExtraBold
    # ("Rounded Mplus 1c") と別の family になり、太さで選べない。v1.060 で原本が直したのと
    # 同じく揃える。
    python3 -I -c '
    import os, sys
    from fontTools.ttLib import TTFont
    font = TTFont(sys.argv[1])
    for record in font["name"].names:
        if record.nameID == 1:
            record.string = "Rounded Mplus 1c"
    font.save(sys.argv[1] + ".tmp")
    os.replace(sys.argv[1] + ".tmp", sys.argv[1])
    ' $out/mods/cheki-agents/fonts/MPLUSRounded1c-Bold.ttf
    # チェキの下の縁の字 (LycoReco と日付)。gpui では字を回せないので、字の形を枠と
    # 同じ傾き (度、負は左回り) に回した svg にしておく。main.js も傾きを memo.js から読む。
    python3 -I ${./mods/cheki-agents/memo.py} \
      $out/mods/cheki-agents/fonts/MPLUSRounded1c-Bold.ttf $out/mods/cheki-agents/fonts/MPLUSRounded1c-Medium.ttf \
      -2 $out/mods/cheki-agents
    echo '{ "place": "none", "title": "Agents" }' > $out/mods/cheki-agents/mod.json

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
