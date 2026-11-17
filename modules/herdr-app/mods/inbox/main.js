// 自分の手を待っている物を 1 か所に並べるモーダル。key で選んで、開く、URL を copy する、session に貼る
// 許可や返事を待っている agent、見ていない間に終わった agent、Slack の依頼、自分の branch の pull request で落ちた CI、自分宛の review 依頼
// 中身を取りに行くのは ./feed.js。開いていない間はタブバーが見に行き、ここは shared に置かれた物を読む
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, ScrollHandle } from "gpui-base";
import { panes, focused, hc, run, notify, theme, shared, props, closeOverlay } from "herdr";
import { waiting, checking, refresh, ask } from "./feed.js";

function ago(ms) {
  const s = Math.max(0, (Date.now() - ms) / 1000);
  if (s < 60) return "now";
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}

// 止まっている agent の画面の最後の数行。たいていは質問か、許可を求める prompt
// 質問とその選択肢が続いている時は、質問から始める
function snippet(text) {
  const lines = (text ?? "").split("\n")
    .map(l => l.replace(/[│─╭╮╰╯┌┐└┘├┤┬┴┼═║▔▁▏▕]/g, " ").replace(/\s+/g, " ").trim())
    .filter(l => /[\p{L}\p{N}]/u.test(l));
  const tail = lines.slice(-8), asked = tail.findLastIndex(l => /[?？]$/.test(l));
  return (asked >= 0 ? tail.slice(asked) : lines.slice(-4)).join(" · ").slice(0, 240);
}

export default class Inbox extends View {
  init(_props, cx) {
    this.snips = {};
    // sel が null の間と、選んでいた行が消えた後は、at の位置の行を選ぶ
    this.sel = null; this.at = 0;
    this.scroll = ScrollHandle.new();
    this.handle = cx.focus_handle();
    this.handle.focus();
    // 開いた直後の focus は dialog の表示に奪われる事があるので、もう一度取る
    cx.timer.after(600, () => this.handle.focus());
    // 開いた時に取り直す。GitHub は前に見てから間が空いている時だけ
    refresh(cx);
    ask(cx);
  }

  // agent が止まった時に一度だけ、その画面を読む。動き出したら捨てる
  read(cx, blocked) {
    for (const address of Object.keys(this.snips)) if (!blocked.some(a => a.address === address)) delete this.snips[address];
    for (const a of blocked) {
      if (a.address in this.snips) continue;
      this.snips[a.address] = "";
      cx.spawn(async cx => {
        const r = await hc(["read", a.address, "--lines", "40"]).catch(() => null);
        if (a.address in this.snips) { this.snips[a.address] = snippet(r?.stdout); cx.notify(); }
      });
    }
  }

  // head が見出しで、他は選べる行。url は copy と paste に使う物で、agent の行には無い。open は Enter で開く物が url と違う時だけ
  rows(w) {
    const name = a => (a.title ?? "").replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}]+/u, "").trim() || a.program?.name || "agent";
    const where = a => `${a.space_name} · ${a.tab_name}`;
    const group = (title, list) => list.length ? [{ key: `head:${title}`, head: `${title} · ${list.length}` }, ...list] : [];
    return [
      ...group("Needs you", w.blocked.map(a => ({ key: `b:${a.address}`, tint: "blocked", title: name(a), side: where(a), body: this.snips[a.address] || null, agent: a.address }))),
      ...group("Finished", w.done.map(a => ({ key: `d:${a.address}`, tint: "done", title: name(a), side: where(a), agent: a.address }))),
      ...group("Slack", w.slack.map(item => ({ key: `s:${item.permalink}`, slack: item, url: item.permalink }))),
      // copy と paste は pull request の URL、Enter は落ちた check
      ...group("CI failed", w.failing.map(pr => ({ key: `c:${pr.url}`, tint: "ansi1", title: `#${pr.number} ${pr.title}`, side: pr.branch,
        body: pr.failed.map(c => c.name).join(" · "), url: pr.url, open: pr.failed.find(c => c.url)?.url }))),
      ...group("Review requested", w.reviews.map(pr => ({ key: `r:${pr.url}`, tint: "accent", title: `#${pr.number} ${pr.title}`, side: ago(Date.parse(pr.updatedAt)),
        body: pr.repository?.nameWithOwner ?? null, url: pr.url }))),
    ];
  }

  // agent はその pane へ移って閉じる。他は browser で開き、続けて次の行を見られるように閉じない
  open(cx, row) {
    if (!row) return;
    if (row.agent) { closeOverlay(props().overlay); run("agent.focus", { terminal: row.agent }); }
    else cx.open_url(row.open ?? row.url);
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
    else if (plain && k === "d") this.settle(cx, row, "tick");
    else if (plain && k === "s") this.settle(cx, row, "skip");
    else if (plain && k === "r") { refresh(cx, true); ask(cx); }
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

  card(t, row, on) {
    return this.frame(t, row, on, t.border)
      .child(h_flex().gap(8).items_center()
        .child(div().size(8).flex_none().rounded(4).bg(t[row.tint]))
        .child(div().flex_1().min_w(0).truncate().font_medium().child(row.title))
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

  render(cx) {
    const t = theme();
    const w = waiting();
    this.read(cx, w.blocked);
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
    const github = shared("inbox.github"), digest = shared("inbox.digest"), sl = digest?.state?.slack;
    const error = shared("inbox.reviews")?.error ?? digest?.error ?? (sl && !sl.connected ? "Slack connector is not signed in" : sl?.error) ?? "";
    const top = (id, label, action) => div().id(id).flex_none().px(6).h(22).flex().items_center().rounded(5).text_size(11).text_color(t.dim).cursor_pointer()
      .hover(s => s.bg(t.hover).text_color(t.foreground)).on_click((_e, cx) => action(cx)).child(label);
    return v_flex().id("inbox").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx, list, at))
      .size_full().min_h(0).rounded(10).overflow_hidden().bg(t.popover).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(svg("mods/inbox/inbox.svg").size(14).text_color(t.muted))
        .child(div().font_semibold().child("Inbox"))
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(error))
        .when(Boolean(sl), el => el.child(top("in-sweep", sl.running ? "sweeping…" : sl.lastAt ? `Slack ${ago(sl.lastAt)}` : "Slack", cx => ask(cx, "/slack/sweep"))))
        .child(top("in-reload", checking() ? "checking…" : github?.at ? `GitHub ${ago(github.at)}` : "GitHub", cx => refresh(cx, true))))
      .child(rows.length
        ? v_flex().id("in-body").flex_1().min_h(0).overflow_y_scrollbar().track_scroll(this.scroll).px(14).pb(12).pt(6).gap(6)
          .children(rows.map(row => row.head ? div().pt(6).text_size(11).font_semibold().text_color(t.muted).child(row.head)
            : row.slack ? this.slack(t, row, row === sel) : this.card(t, row, row === sel)))
        : div().flex_1().p(16).text_color(t.dim).child("Nothing needs you"))
      .when(Boolean(digest?.state), el => el.child(this.standup(t, digest.state.standup)))
      .child(div().flex_none().px(14).py(7).border_t(1).border_color(t.border).truncate().text_size(11).text_color(this.note ? t.muted : t.dim)
        .child(this.note ?? "j/k move · Enter open · y copy URL · p paste to session · d done · s skip · r refresh · Esc close"));
  }
}
