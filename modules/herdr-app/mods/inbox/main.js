// 自分の手を待っている物を 1 か所に並べるモーダル。key で選んで、開く、URL を copy する、session に貼る
// 許可や返事を待っている agent、見ていない間に終わった agent、Slack の依頼、aw-secretary の commitment (自分への約束) のうち手を付けるべき物、自分の branch の pull request で落ちた CI
// 中身を取りに行くのは ./feed.js と ./asks.js。開いていない間はタブバーと左バーの Agents の一覧が見に行き、ここは shared に置かれた物を読む
// Slack と commitment は、開いた時にここで aw-secretary に聞き、答えもここに持つ。dialog の 2 つ目と 3 つ目の面は、open な commitment と閉じた commitment の一覧 (./commitments.js)
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, ScrollHandle } from "gpui-base";
import { panes, focused, run, notify, theme, shared, props, closeOverlay, nextCommand } from "herdr";
import { waiting, checking, refresh } from "./feed.js";
import { readAsks, askOf } from "./asks.js";
import { Secretary, merge } from "./secretary.js";
import { Commitments, WAITING, COLLECTING } from "./commitments.js";
// aw-secretary の API の URL。使わない machine では null (nix が書く: ../../_app-home.nix)
import { COMMITMENTS } from "./env.js";

// commitment が Inbox に出ている訳 (reason) の見出しと、行の印の色
const REASONS = { triage: ["triage", "accent"], overdue: ["overdue", "blocked"], due_soon: ["due soon", "working"], maybe_done: ["done?", "done"] };
// commitment の行で状態を決める key。Slack の行では d と s は tick と skip (FYI の s は seen)
const DECIDE = { a: "active", x: "rejected", d: "done", s: "later", w: "waiting" };
const FACE = { inbox: "Inbox", commitments: "Commitments", closed: "Closed" };
// Esc の action を、on_key_down と同じ key() で扱うための key event
const ESCAPE = { key: "escape", keystroke: "escape", modifiers: {} };

function ago(ms) {
  const s = Math.max(0, (Date.now() - ms) / 1000);
  if (s < 60) return "now";
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}

export default class Inbox extends View {
  init(_props, cx) {
    // sel が null の間と、選んでいた行が消えた後は、at の位置の行を選ぶ
    this.sel = null; this.at = 0;
    this.scroll = ScrollHandle.new();
    this.handle = cx.focus_handle();
    this.handle.focus();
    // 開いた直後の focus は dialog の表示に奪われる事があるので、もう一度取る
    cx.timer.after(600, () => this.handle.focus());
    // commitments は GET /commitments?view=inbox の答えで、読めるまで null。inboxStale は他の面で書いた後の印で、この面を出す時に読み直す
    this.commitments = null; this.commitmentError = null; this.inboxStale = false;
    // slack は GET /slack の答えで、読めるまで null
    this.slack = null; this.slackError = null;
    // URL の無い machine では Commitments と Closed の面を出さない。cms は面の名前ごとの Commitments
    this.sec = new Secretary(COMMITMENTS);
    this.faces = COMMITMENTS ? ["inbox", "commitments", "closed"] : ["inbox"];
    this.face = "inbox";
    this.cms = COMMITMENTS ? { commitments: new Commitments(this, this.sec, "open"), closed: new Commitments(this, this.sec, "closed") } : {};
    // 開いている dialog の面を、keys.json と herdr-app do から選べる: "inbox.commitments" / "inbox.closed" / "inbox.inbox"
    cx.spawn(async cx => { for (;;) { const c = await nextCommand(); if (this.faces.includes(c)) { this.show(c, cx); cx.notify(); } } });
    // Esc は app が key context の Overlay で overlay.close に束ねていて、on_key_down に届く前に dialog を閉じる。より深い key context に束ねた action で先に受ける
    // herdr は keys を読み直すたびに全ての束ねを消すので、開くたびに束ね直す。render の中では束ねられない
    try { cx.bind_keys([{ keystroke: "escape", action: "inbox_escape", context: "InboxDialog" }]); } catch {}
    // 開いた時に取り直す。GitHub は前に見てから間が空いている時だけ
    refresh(cx);
    this.load(cx);
  }

  show(face, cx) {
    if (!this.faces.includes(face)) return;
    this.face = face;
    if (this.cms[face]) this.cms[face].show(cx);
    else if (this.inboxStale) this.load(cx);
  }

  // どの面で書いても、他の面の view は古くなる。出している面はすぐに、他はその面を出す時に読み直す。from は書いた面の Commitments で、Inbox の面からは null
  wrote(cx, from) {
    if (from) this.inboxStale = true;
    for (const cm of Object.values(this.cms)) if (cm !== from) cm.stale = true;
    this.show(this.face, cx);
  }

  // head が見出しで、他は選べる行。url は copy と paste に使う物で、agent の行には無い。open は Enter で開く物が url と違う時だけ
  // mark は commitment の番号。発生源が同じ commitment のある Slack の行にも付ける。open な commitment に紐付いた thread は aw-secretary が Slack に出さないので、普段は付かない
  // Slack の行は aw-secretary が並べた順に出す (急ぎ、依頼、FYI の順で、その中は新しい順)
  rows(w) {
    const slack = this.slack?.items ?? [];
    const name = a => (a.title ?? "").replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}]+/u, "").trim() || a.program?.name || "agent";
    const where = a => `${a.space_name} · ${a.tab_name}`;
    const group = (title, list) => list.length ? [{ key: `head:${title}`, head: `${title} · ${list.length}` }, ...list] : [];
    const links = this.commitments?.links ?? {}, mark = key => links[key] ? `#${links[key]}` : null;
    return [
      ...group("Needs you", w.blocked.map(a => ({ key: `b:${a.address}`, tint: "blocked", title: name(a), side: where(a), body: askOf(a), agent: a.address }))),
      ...group("Finished", w.done.map(a => ({ key: `d:${a.address}`, tint: "done", title: name(a), side: where(a), agent: a.address }))),
      ...group("Slack", slack.map(item => ({ key: `s:${item.permalink}`, slack: item, url: item.permalink, mark: mark(item.key) }))),
      // Enter と copy と paste は、最初の発生源の URL
      ...group("Commitments", (this.commitments?.items ?? []).map(c => ({ key: `m:${c.id}`, commitment: c, tint: REASONS[c.reason]?.[1] ?? "dim", title: c.title, mark: `#${c.id}`,
        side: [REASONS[c.reason]?.[0] ?? c.reason, c.due && `due ${c.due}`].filter(Boolean).join(" · "),
        body: c.summary, url: c.sources[0]?.url ?? null }))),
      // copy と paste は pull request の URL、Enter は落ちた check
      ...group("CI failed", w.failing.map(pr => ({ key: `c:${pr.url}`, tint: "ansi1", title: `#${pr.number} ${pr.title}`, side: pr.branch,
        body: pr.failed.map(c => c.name).join(" · "), url: pr.url, open: pr.failed.find(c => c.url)?.url }))),
    ];
  }

  // agent はその pane へ移って閉じる。他は browser で開き、続けて次の行を見られるように閉じない
  open(cx, row) {
    if (!row) return;
    if (row.agent) { closeOverlay(props().overlay); run("agent.focus", { terminal: row.agent }); }
    else if (row.open ?? row.url) cx.open_url(row.open ?? row.url);
  }

  copy(cx, row) {
    if (!row?.url) return;
    cx.write_to_clipboard(row.url);
    this.note = `Copied ${row.url}`;
  }

  // URL を、開く前に focus していた端末の prompt に貼って閉じる。改行は送らないので、続けて指示を書ける
  // 貼るのは clipboard 越し (terminal.paste) なので、clipboard は URL で上書きされる
  paste(cx, row) {
    if (!row?.url) return;
    const f = focused(), pane = f?.pane ? panes().find(p => p.pane === f.pane) : null;
    if (!pane?.terminal) { notify({ title: "Inbox", body: "Focus a terminal pane first, then paste again", level: "warning" }); return; }
    cx.write_to_clipboard(`${row.url} `);
    run("terminal.paste");
    closeOverlay(props().overlay);
    run("pane.focus", { pane: pane.pane });
  }

  // Slack の行を片付け、答えの view で置き換える。tick は依頼を済ませた、skip は依頼を見送る、seen は FYI を読んだ印
  settle(cx, row, op) {
    if (!row?.slack || (row.slack.kind === "ask" ? op === "seen" : op !== "seen")) return;
    if (this.slack?.running) { this.note = COLLECTING; return; }
    const sent = this.sec.write(cx, "/slack/items", { op, ids: [row.slack.permalink] }, got => {
      if (this.note === WAITING) this.note = null;
      this.slack = merge(this.slack, got); this.slackError = got.error;
    });
    if (!sent) this.note = WAITING;
  }

  loadSlack(cx) {
    this.sec.read(cx, "slack", "/slack", got => { this.slack = merge(this.slack, got); this.slackError = got.error; });
  }

  // inbox の view と Slack を読む。open な commitment に紐付いた thread は Slack に出ないので、commitment を変えたら Slack も読み直す
  load(cx) {
    this.inboxStale = false;
    this.sec.read(cx, "inbox", "/commitments?view=inbox", got => { this.commitments = merge(this.commitments, got); this.commitmentError = got.error; });
    this.loadSlack(cx);
  }

  // commitment の状態を決め、答えの inbox の view で置き換える。collect の最中は aw-secretary が書かせないので、送らない
  decide(cx, row, status) {
    if (this.commitments?.running) { this.note = COLLECTING; return; }
    const sent = this.sec.write(cx, `/commitments/${row.commitment.id}`, { status }, (got, cx) => {
      if (this.note === WAITING) this.note = null;
      this.commitments = merge(this.commitments, got); this.commitmentError = got.error;
      this.loadSlack(cx);
      this.wrote(cx, null);
    });
    if (!sent) this.note = WAITING;
  }

  key(e, cx, list, at) {
    const m = e.modifiers ?? {}, k = e.key, row = list[at], cm = this.cms[this.face] ?? null;
    if (m.alt || m.platform) return;
    const plain = !m.control && !m.shift;
    // 入力欄と、面の上に重ねた一覧には、その面が先に聞く。入力欄に流す key は止めない
    if (cm?.typing || cm?.overlay) { if (!cm.modal(e, cx)) return; }
    else {
      this.note = null;
      if (k === "escape" && cm?.filter) cm.refilter("", cx);
      // 入力欄が先に focus を手放した Esc では、typing が外れていても dialog は focus を持っていない。閉じずに focus を取り戻す
      else if (k === "escape" && !this.handle.is_focused()) this.handle.focus();
      else if (k === "escape") closeOverlay(props().overlay);
      else if (k === "tab" && !m.control) this.show(this.faces[(this.faces.indexOf(this.face) + 1) % this.faces.length], cx);
      else if (plain && /^[1-9]$/.test(k)) this.show(this.faces[Number(k) - 1], cx);
      // Commitments と Closed の面の書く key は、Ctrl 付きでは効かせない。Ctrl は移動だけ
      else if (cm && m.control) { if (k === "j" || k === "n") cm.move(1, cx); else if (k === "k" || k === "p") cm.move(-1, cx); }
      else if (cm) cm.key(e, cx);
      else if (k === "enter") this.open(cx, row);
      else if (k === "down" || plain && k === "j" || m.control && (k === "j" || k === "n")) this.move(list, at, 1);
      else if (k === "up" || plain && k === "k" || m.control && (k === "k" || k === "p")) this.move(list, at, -1);
      else if (plain && k === "y") this.copy(cx, row);
      else if (plain && k === "p") this.paste(cx, row);
      else if (plain && row?.commitment && Object.hasOwn(DECIDE, k)) this.decide(cx, row, DECIDE[k]);
      else if (plain && k === "d") this.settle(cx, row, "tick");
      else if (plain && k === "s") this.settle(cx, row, row?.slack?.kind === "ask" ? "skip" : "seen");
      else if (plain && k === "r") { refresh(cx, true); this.load(cx); }
      // 取り消しは Commitments の面と同じ。この dialog で書いた操作を、面を問わず新しい物から戻す
      else if (plain && k === "u" && this.cms.commitments) this.cms.commitments.undo(cx);
    }
    // 他の key も下の端末へは流さない
    cx.stop_propagation();
    cx.notify();
  }

  move(list, at, step) {
    const row = list[Math.min(list.length - 1, Math.max(0, at + step))];
    if (row) this.sel = row.key;
  }

  chip(t, id, label, action) {
    return div().id(id).flex_none().px(7).h(20).flex().items_center().rounded(5).border_1().border_color(t.border).text_size(11).text_color(t.muted).cursor_pointer()
      .hover(s => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => { cx.stop_propagation(); action(cx); }).child(label);
  }

  // click は Enter と同じ
  frame(t, row, on, edge) {
    return v_flex().id(`in-${row.key}`).px(10).py(8).gap(4).rounded(8).border_1().border_color(on ? t.accent : edge).bg(on ? t.selected : t.raised).cursor_pointer()
      .hover(s => s.border_color(t.accent)).on_click((_e, cx) => { this.sel = row.key; this.open(cx, row); cx.notify(); });
  }

  // commitment の番号の印。commitment の行と、同じ発生源の行で同じ見た目にする
  mark(t, row) {
    return div().flex_none().px(5).h(16).flex().items_center().rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.muted).child(row.mark);
  }

  card(t, row, on) {
    return this.frame(t, row, on, t.border)
      .child(h_flex().gap(8).items_center()
        .child(div().size(8).flex_none().rounded(4).bg(t[row.tint]))
        .child(div().flex_1().min_w(0).truncate().font_medium().child(row.title))
        .when(Boolean(row.mark), el => el.child(this.mark(t, row)))
        .child(div().flex_none().max_w(220).truncate().text_size(11).text_color(t.dim).child(row.side)))
      .when(Boolean(row.body), el => el.child(div().text_size(12).text_color(t.muted).child(row.body)));
  }

  // Slack の依頼と FYI。Done は片付けた、Skip は見送る、Seen は FYI を読んだ印
  slackCard(t, row, on) {
    const item = row.slack, asked = item.kind === "ask";
    return this.frame(t, row, on, item.urgent ? t.blocked : t.border)
      .child(h_flex().gap(8).items_center()
        .child(div().size(8).flex_none().rounded(4).bg(item.urgent ? t.blocked : asked ? t.accent : t.dim))
        .child(div().flex_1().min_w(0).truncate().font_medium().child(item.from))
        .when(Boolean(row.mark), el => el.child(this.mark(t, row)))
        .child(div().flex_none().max_w(220).truncate().text_size(11).text_color(t.dim).child(item.channel)))
      .child(div().text_size(12).text_color(t.muted).child(item.text))
      .child(h_flex().gap(6).items_center()
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(item.due ? t.working : t.dim).child(item.due || ago(Date.parse(item.askedAt))))
        .when(asked, el => el.child(this.chip(t, `in-done-${row.key}`, "Done", cx => this.settle(cx, row, "tick")))
          .child(this.chip(t, `in-skip-${row.key}`, "Skip", cx => this.settle(cx, row, "skip"))))
        .when(!asked, el => el.child(this.chip(t, `in-seen-${row.key}`, "Seen", cx => this.settle(cx, row, "seen")))));
  }

  // 下端の key の案内。選んでいる行で効く key だけを出す
  hint(row) {
    const keys = ["j/k move", "Enter open"], wait = "wait until aw-secretary finishes collecting, then r";
    if (row?.url) keys.push("y copy URL", "p paste to session");
    if (row?.slack) keys.push(...(this.slack?.running ? [`d/s ${wait}`] : row.slack.kind === "ask" ? ["d done", "s skip"] : ["s seen"]));
    if (row?.commitment) keys.push(...(this.commitments?.running ? [`a/x/d/s/w ${wait}`] : ["a adopt", "x reject", "d done", "s later", "w waiting"]));
    return [...keys, "r refresh", ...(this.cms.commitments ? ["u undo", "Tab face"] : []), "Esc close"].join(" · ");
  }

  render(cx) {
    const t = theme();
    const w = waiting();
    readAsks(cx, w.blocked);
    const rows = this.rows(w), list = rows.filter(r => !r.head);
    let at = list.findIndex(r => r.key === this.sel);
    if (at < 0) at = Math.max(0, Math.min(this.at, list.length - 1));
    this.at = at;
    const sel = list[at];
    // 選んだ行が見えるようにする。先頭の行では、その見出しも一緒に見せる
    if (sel && this.seen !== sel.key) {
      this.seen = sel.key;
      const shown = rows.indexOf(sel);
      this.scroll.scroll_to_item(shown === 1 ? 0 : shown);
    }
    const github = shared("inbox.github"), sl = this.slack, face = this.face, board = this.cms[face];
    // 見出しの commitment の時刻と error は、出している面の view の物
    const cm = board ? board.view : this.commitments;
    const error = (board ? board.error : this.commitmentError ?? this.slackError) ?? "";
    const top = (id, label, action) => div().id(id).flex_none().px(6).h(22).flex().items_center().rounded(5).text_size(11).text_color(t.dim).cursor_pointer()
      .hover(s => s.bg(t.hover).text_color(t.foreground)).on_click((_e, cx) => action(cx)).child(label);
    return v_flex().id("inbox").key_context("InboxDialog").on_action("inbox_escape", (_e, cx) => this.key(ESCAPE, cx, list, at))
      .track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx, list, at))
      .size_full().min_h(0).rounded(10).overflow_hidden().bg(t.popover).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(svg("mods/inbox/inbox.svg").size(14).text_color(t.muted))
        .child(div().font_semibold().child("Inbox"))
        .when(this.faces.length > 1, el => el.child(div().w(4)).children(this.faces.map((f, i) => div().id(`in-face-${f}`).flex_none().px(8).h(24).flex().items_center()
          .rounded(6).text_size(12).cursor_pointer().text_color(f === face ? t.foreground : t.muted).when(f === face, el => el.bg(t.selected)).hover(s => s.bg(t.hover))
          .on_click((_e, cx) => { this.show(f, cx); this.handle.focus(); cx.notify(); }).child(`${i + 1} ${FACE[f]}`))))
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(error))
        // Slack を集めるのも aw-secretary の collect で、その時刻を出す
        .when(face === "inbox" && Boolean(sl), el => el.child(div().flex_none().px(6).text_size(11).text_color(t.dim)
          .child(sl.lastCollectAt ? `Slack ${ago(Date.parse(sl.lastCollectAt))}` : "Slack")))
        // collect の最中は commitment を変えられない
        .when(Boolean(cm) || Boolean(COMMITMENTS) && this.sec.busy, el => el.child(div().flex_none().px(6).text_size(11).text_color(cm?.running ? t.working : t.dim)
          .child(!cm ? "Commitments…" : cm.running ? "collecting…" : cm.lastCollectAt ? `Commitments ${ago(Date.parse(cm.lastCollectAt))}` : "Commitments")))
        .child(top("in-reload", checking() ? "checking…" : github?.at ? `GitHub ${ago(github.at)}` : "GitHub", cx => refresh(cx, true))))
      .child(board ? board.render(t, this.handle) : rows.length
        ? v_flex().id("in-body").flex_1().min_h(0).overflow_y_scrollbar().track_scroll(this.scroll).px(14).pb(12).pt(6).gap(6)
          .children(rows.map(row => row.head ? div().pt(6).text_size(11).font_semibold().text_color(t.muted).child(row.head)
            : row.slack ? this.slackCard(t, row, row === sel) : this.card(t, row, row === sel)))
        : div().flex_1().p(16).text_color(t.dim).child("Nothing needs you"))
      .child(div().flex_none().px(14).py(7).border_t(1).border_color(t.border).truncate().text_size(11).text_color(this.note ? t.muted : t.dim)
        .child(this.note ?? (board ? board.hint() : this.hint(sel))));
  }
}
