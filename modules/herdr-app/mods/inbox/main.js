// 自分の手を待っている物を 1 か所に並べるモーダル。key で選んで、開く、URL を copy する、session に貼る
// 許可や返事を待っている agent、見ていない間に終わった agent、Slack の依頼、aw-secretary の commitment (自分への約束) のうち手を付けるべき物、自分の branch の pull request で落ちた CI
// 中身を取りに行くのは ./feed.js と ./asks.js。開いていない間はタブバーと左バーの Agents の一覧が見に行き、ここは shared に置かれた物を読む
// commitment だけは、開いた時にここで aw-secretary に聞き、答えもここに持つ
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, ScrollHandle } from "gpui-base";
import { panes, focused, run, notify, theme, shared, props, closeOverlay } from "herdr";
import { waiting, checking, refresh, ask } from "./feed.js";
import { readAsks, askOf } from "./asks.js";
// aw-secretary の API の URL。使わない machine では null (nix が書く: ../../_show.nix)
import { COMMITMENTS } from "./env.js";

// commitment が Inbox に出ている訳 (reason) の見出しと、行の印の色
const REASONS = { triage: ["triage", "accent"], overdue: ["overdue", "blocked"], due_soon: ["due soon", "working"], maybe_done: ["done?", "done"] };
// commitment の行で状態を決める key。Slack の行では d と s は tick と skip
const DECIDE = { a: "active", x: "rejected", d: "done", s: "later", w: "waiting" };
// 答えを待っている間に key を押した時の note。答えが返ったら消す
const WAITING = "Waiting for aw-secretary to answer";

// Slack の permalink を、aw-secretary の links の key (slack:<channel>:<thread の root の ts>) にする。返信の permalink は thread_ts の root に寄せる
const slackKey = url => { const m = /\/archives\/([A-Z0-9]+)\/p(\d+)(\d{6})/.exec(url ?? ""); if (!m) return null; const t = /[?&]thread_ts=(\d+\.\d+)/.exec(url); return `slack:${m[1]}:${t ? t[1] : `${m[2]}.${m[3]}`}`; };

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
    // commitments は GET /commitments?view=inbox の答えで、読めるまで null
    this.commitments = null; this.commitmentError = null; this.consulting = false;
    // 開いた時に取り直す。GitHub は前に見てから間が空いている時だけ
    refresh(cx);
    ask(cx);
    this.consult(cx);
  }

  // head が見出しで、他は選べる行。url は copy と paste に使う物で、agent の行には無い。open は Enter で開く物が url と違う時だけ
  // mark は commitment の番号。発生源が同じ commitment のある Slack の行にも付ける。どちらの行も残す
  rows(w) {
    const name = a => (a.title ?? "").replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}]+/u, "").trim() || a.program?.name || "agent";
    const where = a => `${a.space_name} · ${a.tab_name}`;
    const group = (title, list) => list.length ? [{ key: `head:${title}`, head: `${title} · ${list.length}` }, ...list] : [];
    const links = this.commitments?.links ?? {}, mark = key => links[key] ? `#${links[key]}` : null;
    return [
      ...group("Needs you", w.blocked.map(a => ({ key: `b:${a.address}`, tint: "blocked", title: name(a), side: where(a), body: askOf(a), agent: a.address }))),
      ...group("Finished", w.done.map(a => ({ key: `d:${a.address}`, tint: "done", title: name(a), side: where(a), agent: a.address }))),
      ...group("Slack", w.slack.map(item => ({ key: `s:${item.permalink}`, slack: item, url: item.permalink, mark: mark(slackKey(item.permalink)) }))),
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

  // Slack の行を片付ける。tick は依頼を済ませた印で、FYI には無い。skip は依頼なら見送る、FYI なら読んだ印
  settle(cx, row, op) {
    if (!row?.slack || op === "tick" && row.slack.kind !== "ask") return;
    ask(cx, "/slack/items", { op, ids: [row.slack.permalink] });
  }

  // aw-secretary に聞く。id が無ければ inbox の view を読むだけ。id があれば body で commitment を変え、変えた後の view を受け取る
  // 聞くのは開いている Inbox の中で 1 度に 1 つで、答えが返るまで次を送らない。答えの順が入れ替わらず、続けて押した時に server で後の物が先に適用されない
  // 答えを待ったまま閉じると、次に開いた Inbox はその答えを待たない
  consult(cx, id, body) {
    if (!COMMITMENTS || this.consulting) return;
    this.consulting = true;
    cx.spawn(async cx => {
      try {
        const r = await (id
          ? fetch(`${COMMITMENTS}/commitments/${id}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) })
          : fetch(`${COMMITMENTS}/commitments?view=inbox`));
        if (r.ok) { this.commitments = await r.json(); this.commitmentError = null; }
        else {
          // 書けなかった時は前の view を残して error だけを出す。collect の最中の 503 は running: true が付くので、key を止める
          const e = await r.json().catch(() => null);
          this.commitmentError = e?.error ?? `aw-secretary answered ${r.status}`;
          if (e?.running && this.commitments) this.commitments = { ...this.commitments, running: true };
        }
      } catch (e) { this.commitmentError = String(e?.message ?? e); }
      finally {
        this.consulting = false;
        if (this.note === WAITING) this.note = null;
        cx.notify();
      }
    });
  }

  // commitment の状態を決める。collect の最中は aw-secretary が書かせないので、送らない
  decide(cx, row, status) {
    if (this.commitments?.running) this.note = "aw-secretary is collecting. Press r after it finishes, then try again";
    else if (this.consulting) this.note = WAITING;
    else this.consult(cx, row.commitment.id, { status });
  }

  key(e, cx, list, at) {
    const m = e.modifiers ?? {}, k = e.key, row = list[at];
    if (m.alt || m.platform) return;
    const plain = !m.control && !m.shift;
    this.note = null;
    if (k === "escape") closeOverlay(props().overlay);
    else if (k === "enter") this.open(cx, row);
    else if (k === "down" || k === "tab" && !m.shift || plain && k === "j" || m.control && (k === "j" || k === "n")) this.move(list, at, 1);
    else if (k === "up" || k === "tab" || plain && k === "k" || m.control && (k === "k" || k === "p")) this.move(list, at, -1);
    else if (plain && k === "y") this.copy(cx, row);
    else if (plain && k === "p") this.paste(cx, row);
    else if (plain && row?.commitment && Object.hasOwn(DECIDE, k)) this.decide(cx, row, DECIDE[k]);
    else if (plain && k === "d") this.settle(cx, row, "tick");
    else if (plain && k === "s") this.settle(cx, row, "skip");
    else if (plain && k === "r") { refresh(cx, true); ask(cx); this.consult(cx); }
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
  slack(t, row, on) {
    const item = row.slack, asked = item.kind === "ask";
    return this.frame(t, row, on, item.urgent ? t.blocked : t.border)
      .child(h_flex().gap(8).items_center()
        .child(div().size(8).flex_none().rounded(4).bg(item.urgent ? t.blocked : asked ? t.accent : t.dim))
        .child(div().flex_1().min_w(0).truncate().font_medium().child(item.from))
        .when(Boolean(row.mark), el => el.child(this.mark(t, row)))
        .child(div().flex_none().max_w(220).truncate().text_size(11).text_color(t.dim).child(item.channel)))
      .child(div().text_size(12).text_color(t.muted).child(item.text))
      .child(h_flex().gap(6).items_center()
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(item.due ? t.working : t.dim).child(item.due || ago(item.at)))
        .when(asked, el => el.child(this.chip(t, `in-done-${row.key}`, "Done", cx => this.settle(cx, row, "tick")))
          .child(this.chip(t, `in-skip-${row.key}`, "Skip", cx => this.settle(cx, row, "skip"))))
        .when(!asked, el => el.child(this.chip(t, `in-seen-${row.key}`, "Seen", cx => this.settle(cx, row, "skip")))));
  }

  // standup の下書き。Copy は Slack 等にそのまま貼れる箇条書きで clipboard に入れる
  standup(t, d) {
    const text = d.bullets.map(b => `- ${b}`).join("\n");
    return v_flex().flex_none().px(14).py(10).gap(6).border_t(1).border_color(t.border).bg(t.chrome)
      .child(h_flex().gap(6).items_center()
        .child(div().flex_1().min_w(0).truncate().text_size(11).font_semibold().text_color(t.muted)
          .child(`Standup${d.day ? ` · ${d.label} ${d.day}` : ""}${d.running ? " · writing…" : d.writtenAt ? ` · ${ago(d.writtenAt)}` : ""}`))
        .when(Boolean(d.bullets.length), el => el.child(this.chip(t, "in-su-copy", this.copied === text ? "Copied" : "Copy", cx => { cx.write_to_clipboard(text); this.copied = text; cx.notify(); })))
        .when(!d.running, el => el.child(this.chip(t, "in-su-write", "Write now", cx => ask(cx, "/standup/write")))))
      .when(Boolean(d.error), el => el.child(div().text_size(11).text_color(t.blocked).child(d.error)))
      .child(d.bullets.length
        ? v_flex().id("in-su-body").max_h(200).overflow_y_scrollbar().gap(3).children(d.bullets.map(b => h_flex().gap(6).items_start().text_size(12)
          .child(div().flex_none().text_color(t.dim).child("•")).child(div().flex_1().min_w(0).child(b))))
        : div().text_size(12).text_color(t.dim).child(d.running ? "" : "No draft yet"));
  }

  // 下端の key の案内。選んでいる行で効く key だけを出す
  hint(row, collecting) {
    const keys = ["j/k move", "Enter open"];
    if (row?.url) keys.push("y copy URL", "p paste to session");
    if (row?.slack) keys.push(...(row.slack.kind === "ask" ? ["d done", "s skip"] : ["s seen"]));
    if (row?.commitment) keys.push(...(collecting ? ["a/x/d/s/w wait until aw-secretary finishes collecting, then r"] : ["a adopt", "x reject", "d done", "s later", "w waiting"]));
    return [...keys, "r refresh", "Esc close"].join(" · ");
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
    const github = shared("inbox.github"), digest = shared("inbox.digest"), sl = digest?.state?.slack, cm = this.commitments;
    const error = this.commitmentError ?? digest?.error ?? (sl && !sl.connected ? "Slack connector is not signed in" : sl?.error) ?? "";
    const top = (id, label, action) => div().id(id).flex_none().px(6).h(22).flex().items_center().rounded(5).text_size(11).text_color(t.dim).cursor_pointer()
      .hover(s => s.bg(t.hover).text_color(t.foreground)).on_click((_e, cx) => action(cx)).child(label);
    return v_flex().id("inbox").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx, list, at))
      .size_full().min_h(0).rounded(10).overflow_hidden().bg(t.popover).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(svg("mods/inbox/inbox.svg").size(14).text_color(t.muted))
        .child(div().font_semibold().child("Inbox"))
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(error))
        .when(Boolean(sl), el => el.child(top("in-sweep", sl.running ? "sweeping…" : sl.lastAt ? `Slack ${ago(sl.lastAt)}` : "Slack", cx => ask(cx, "/slack/sweep"))))
        // collect の最中は commitment を変えられない
        .when(Boolean(cm) || this.consulting, el => el.child(div().flex_none().px(6).text_size(11).text_color(cm?.running ? t.working : t.dim)
          .child(!cm ? "Commitments…" : cm.running ? "collecting…" : cm.lastCollectAt ? `Commitments ${ago(Date.parse(cm.lastCollectAt))}` : "Commitments")))
        .child(top("in-reload", checking() ? "checking…" : github?.at ? `GitHub ${ago(github.at)}` : "GitHub", cx => refresh(cx, true))))
      .child(rows.length
        ? v_flex().id("in-body").flex_1().min_h(0).overflow_y_scrollbar().track_scroll(this.scroll).px(14).pb(12).pt(6).gap(6)
          .children(rows.map(row => row.head ? div().pt(6).text_size(11).font_semibold().text_color(t.muted).child(row.head)
            : row.slack ? this.slack(t, row, row === sel) : this.card(t, row, row === sel)))
        : div().flex_1().p(16).text_color(t.dim).child("Nothing needs you"))
      .when(Boolean(digest?.state), el => el.child(this.standup(t, digest.state.standup)))
      .child(div().flex_none().px(14).py(7).border_t(1).border_color(t.border).truncate().text_size(11).text_color(this.note ? t.muted : t.dim)
        .child(this.note ?? this.hint(sel, cm?.running)));
  }
}
