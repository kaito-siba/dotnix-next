// Inbox の dialog の 2 つ目と 3 つ目の面。aw-secretary の commitment の TUI (aw-secretary commitments) を GUI にした物
// 左に commitment を状態ごとに並べ、右に選んだ行の詳細を出す。読み書きは ./secretary.js を通す
// mode が open の面は open な commitment を、closed の面は 30 日以内に閉じた commitment を並べる
import { div } from "gpui-kit";
import { v_flex, h_flex, v_virtual_list, VirtualListScrollHandle, Scrollbar, InputState, Input } from "gpui-base";
import { merge } from "./secretary.js";

const ROW = 27, HEAD = 30;
// closed の節の中は、aw-secretary が返す閉じた新しい順のまま並べる
const SECTIONS = {
  open: [["candidate", "Candidates"], ["active", "Active"], ["waiting", "Waiting"], ["later", "Later"]],
  closed: [["expired", "Expired"], ["done", "Done"], ["rejected", "Rejected"]],
};
const STATUS = { candidate: "Candidate", active: "Active", waiting: "Waiting", later: "Later", done: "Done", rejected: "Rejected", expired: "Expired" };
const DOT = { candidate: "accent", active: "done", done: "done", expired: "working" };
const REASON = { triage: "triage", overdue: "overdue", due_soon: "due soon", maybe_done: "done?" };
// 入力欄の使い道ごとの見出し
const PROMPT = { due: "Due YYYY-MM-DD · empty clears it", memo: "Memo", title: "Title", source: "Add a source by its Slack or GitHub URL", correct: "Correction for the extract", filter: "Filter by title" };
const DECIDE = { a: "active", x: "rejected", w: "waiting", l: "later", d: "done" };
// open の面の w と l は、その状態と進行中を行き来する
const TOGGLE = new Set(["w", "l"]);
// aw-secretary に書く key。collect の最中と、前の書き込みの答えを待っている間は受けない
const WRITES = { open: new Set([..."axwldtnTNfu"]), closed: new Set([..."axwldtnTu"]) };
export const WAITING = "Waiting for aw-secretary to answer the last change";
export const COLLECTING = "aw-secretary is collecting. Press r after it finishes, then try again";

// 2026-11-17T18:02:00+09:00 を 11/17 18:02 にする
const stamp = at => `${at.slice(5, 10).replace("-", "/")} ${at.slice(11, 16)}`;
// 発生源の種類ごとの件数。G2 S1 のように出す (TUI の source_badge と同じ)
function badge(sources) {
  const n = { github: 0, slack: 0 };
  for (const s of sources) n[s.source] = (n[s.source] ?? 0) + 1;
  return [["github", "G"], ["slack", "S"]].filter(([k]) => n[k]).map(([k, l]) => n[k] > 1 ? `${l}${n[k]}` : l).join(" ");
}

export class Commitments {
  // owner は Inbox の View。focus を戻す handle と、下端の note と、書いた後に他の面を古いと印す wrote を持つ
  // mode は open か closed で、読む view と、書いた後に答えてもらう view の名前
  constructor(owner, secretary, mode) {
    this.owner = owner; this.sec = secretary; this.mode = mode;
    // view は GET /commitments?view=<mode> の答えで、読めるまで null。stale は他の面で書いた後の印で、この面を出す時に読み直す
    this.view = null; this.error = null; this.stale = false;
    // GET /commitments/<id> の答え (notes と events)。書いた行の分は捨てて読み直す
    this.details = new Map();
    // sel は選んでいる commitment の id。選んでいた行が消えた後は、at の位置の行を選ぶ
    this.sel = null; this.at = 0; this.filter = "";
    // typing は入力欄の使い道 (PROMPT の key)。null は入力していない。target は入力欄を開いた時に選んでいた commitment の id で、決めた値はそこへ書く
    this.typing = null; this.opening = null; this.target = null;
    // 面の上に重ねる一覧: 開く発生源を選ぶ (choose) か、前回の朝レポートからの差分 (diff)
    this.overlay = null; this.unsure = false;
    this.scroll = VirtualListScrollHandle.new();
    this.input = InputState.new({ placeholder: "" });
    this.input.on("change", (_e, cx) => {
      // 入力欄を開いた key がそのまま入力される事があるので捨てる
      const o = this.opening, v = this.input.value();
      this.opening = null;
      if (o && (v === o.value + o.key || v === o.key + o.value)) { this.input.set_value(o.value); return; }
      if (this.typing === "filter") this.refilter(v, cx);
    });
    this.input.on("submit", (_e, cx) => this.submit(cx));
    this.input.on("blur", (_e, cx) => { if (this.typing) { this.typing = null; cx.notify(); } });
  }

  // この面を出す時に呼ぶ。他の面で書いた後は、覚えている詳細も古い事があるので捨てる
  show(cx) { if (this.stale) this.reload(cx); else if (!this.view) this.load(cx); }

  // 読みの key は面ごとに分ける。Secretary の drop で、もう 1 つの面の読みを捨てない
  load(cx) {
    this.stale = false;
    this.sec.read(cx, this.mode, `/commitments?view=${this.mode}`, (got, cx) => { this.take(got); this.reveal(); this.want(cx); });
  }

  reload(cx) { this.details.clear(); this.load(cx); }

  take(got) {
    this.view = merge(this.view, got);
    this.error = got.error;
  }

  rows() {
    const q = this.filter.toLowerCase(), items = (this.view?.items ?? []).filter(c => !q || c.title.toLowerCase().includes(q));
    return SECTIONS[this.mode].flatMap(([status, title]) => {
      const list = items.filter(c => c.status === status);
      return list.length ? [{ key: `h:${status}`, head: title, n: list.length, status }, ...list.map(c => ({ key: `c:${c.id}`, item: c }))] : [];
    });
  }

  selected(rows = this.rows()) {
    const list = rows.filter(r => !r.head);
    let at = list.findIndex(r => r.item.id === this.sel);
    if (at < 0) at = Math.max(0, Math.min(this.at, list.length - 1));
    this.at = at;
    return list[at] ?? null;
  }

  move(step, cx) {
    const rows = this.rows(), list = rows.filter(r => !r.head), at = list.indexOf(this.selected(rows));
    const to = list[Math.min(list.length - 1, Math.max(0, at + step))];
    if (!to) return;
    this.sel = to.item.id;
    this.scroll.scroll_to_item(rows.indexOf(to), "center");
    this.want(cx);
  }

  // 選んでいる行を見せる。書いた後や読み直した後は、その行が別の節へ移っている事がある
  reveal() {
    const rows = this.rows(), sel = this.selected(rows);
    if (sel) this.scroll.scroll_to_item(rows.indexOf(sel), "center");
  }

  // 絞り込みが変わると選んでいる行も変わるので、その行を見せて詳細を読む
  refilter(filter, cx) {
    this.filter = filter;
    this.reveal();
    this.want(cx);
    cx.notify();
  }

  // 選んでいる行の notes と events を読む。j/k で続けて動いた時は、止まった行の分だけを読む
  want(cx) {
    const c = this.selected()?.item;
    const key = `${this.mode}:detail`;
    if (!c || this.details.has(c.id)) return this.sec.drop(key);
    this.sec.read(cx, key, `/commitments/${c.id}`, got => { if (got.answer) this.details.set(c.id, got.answer); else this.error = got.error; });
  }

  // 書いて、答えのこの面の view で置き換える。他の面の view は読み直す。答えを待つ間にその面へ移っていればすぐに、居なければその面を出す時に
  write(cx, path, body, then) {
    if (this.view?.running) { this.owner.note = COLLECTING; return; }
    this.send(cx, path, body, then);
  }

  // collect の最中かを見ずに書く。見ていない面の view の running は古い事がある。collect の最中なら aw-secretary が 503 で断る
  send(cx, path, body, then) {
    const sent = this.sec.write(cx, path, body, (got, cx) => {
      if (this.owner.note === WAITING) this.owner.note = null;
      this.take(got);
      then?.(got, cx);
      this.owner.wrote(cx, this);
      this.reveal();
      this.want(cx);
    });
    if (!sent) this.owner.note = WAITING;
  }

  change(cx, c, body) { this.write(cx, `/commitments/${c.id}?view=${this.mode}`, body, () => this.details.delete(c.id)); }

  // 入力欄を開く (使い道と、開いた key と、初めの値)、または閉じる
  type(mode, cx, key = null, value = "") {
    const was = this.typing;
    this.typing = mode;
    if (mode) {
      this.opening = key && { key, value };
      this.target = this.selected()?.item.id ?? null;
      this.input.set_value(value);
      this.input.focus();
    } else if (was) this.owner.handle.focus();
    cx.notify();
  }

  submit(cx) {
    const mode = this.typing, v = this.input.value().trim(), c = this.view?.items.find(c => c.id === this.target);
    this.type(null, cx);
    if (mode === "source" && v) this.write(cx, `/sources?view=${this.mode}`, { url: v }, got => this.registered(got));
    else if (mode === "filter") return;
    // 入力している間に読み直して、その commitment がこの面の view から外れた
    else if (!c) this.owner.note = `The commitment was ${this.mode === "open" ? "closed" : "reopened"} while you were typing. Nothing was saved`;
    else if (mode === "due") this.change(cx, c, { due: v || null });
    else if (mode === "memo") this.change(cx, c, { notes: v || null });
    else if (mode === "title" && v) this.change(cx, c, { title: v });
    else if (mode === "correct" && v) this.write(cx, `/commitments/${c.id}/corrections?view=${this.mode}`, { text: v }, got => {
      if (got.answer) { this.owner.note = `Recorded. ${got.answer.reset ?? 0} raw items will be extracted again at the next extract`; this.details.delete(c.id); }
    });
  }

  // 抽出は aw-secretary の別の process で数十秒かかるので、新しく登録した URL の commitment は、その後に読み直すまで出ない
  registered(got) {
    const a = got.answer;
    if (!a) return;
    // 紐付いた commitment を選ぶ。絞り込みに合わない事があるので、絞り込みは外す
    if (a.commitment) { this.sel = a.commitment; this.filter = ""; }
    this.owner.note = got.status === 200 ? `${a.source.label} is already watched${a.commitment ? ` (#${a.commitment})` : ""}`
      : a.extracting ? `Registered ${a.source.label}. It is being extracted now; press r in a moment`
      : `Registered ${a.source.label}. It will be extracted at the next collect`;
  }

  // 発生源を開く。複数あれば選ばせる
  open(cx, c) {
    const sources = c.sources.filter(s => s.url);
    if (!sources.length) this.owner.note = "This commitment has no source URL";
    else if (sources.length === 1) cx.open_url(sources[0].url);
    else this.overlay = { kind: "choose", sources, at: 0 };
  }

  diff(cx) {
    this.overlay = { kind: "diff", since: null, events: null, at: 0, scroll: VirtualListScrollHandle.new() };
    const shown = this.overlay;
    this.sec.read(cx, `${this.mode}:diff`, "/events", got => {
      if (got.answer) Object.assign(shown, { since: got.answer.since, events: got.answer.events ?? [] });
      else Object.assign(shown, { events: [], error: got.error });
    });
  }

  // この dialog で書いた操作を、新しい物から 1 つ取り消す。列は aw-secretary が dialog ごとに持ち、Inbox の面の Slack の行の操作も入る。戻せない時の理由 (列が空、後に別の書き込みがあった) は、この面では見出しに、Inbox の面では下端に出す
  // 落ちて答えが無かった取り消しは、aw-secretary で済んだかが分からない。送り直すと 1 つ前の操作まで戻るので、次の u は 1 度止めて知らせる
  undo(cx) {
    if (this.unsure) {
      this.unsure = false;
      this.owner.note = "The last undo may have gone through. Press r to check, then u again to undo the one before it";
      return;
    }
    // Inbox の面からも呼ぶので、この面の view の running では止めない
    this.send(cx, `/undo?view=${this.mode}`, {}, got => {
      const u = got.answer?.undone;
      this.unsure = !got.answer && (got.status === null || got.status < 300);
      // 答えには Slack の view も付くので、Inbox の面の Slack の行も置き換える
      if (got.answer?.slack) this.owner.slack = got.answer.slack;
      if (!u) { if (this.owner.face === "inbox") this.owner.note = got.error; return; }
      if (u.target === "slack") { this.owner.note = `Undid ${u.label}${u.title ? `: ${u.title}` : ""}`; return; }
      this.owner.note = `Undid ${u.label}: #${u.id} ${u.title ?? ""}`;
      this.sel = u.id; this.details.delete(u.id);
    });
  }

  // 入力欄と重ねた一覧の key。false を返したら、key を入力欄へ流す
  modal(e, cx) {
    const k = e.key, o = this.overlay;
    if (this.typing) {
      if (k === "escape") { if (this.typing === "filter") this.refilter("", cx); this.type(null, cx); }
      else if (this.typing === "filter" && (k === "down" || k === "up")) this.move(k === "down" ? 1 : -1, cx);
      else return false;
    } else if (k === "escape") this.overlay = null;
    else if (o.kind === "choose") {
      const pick = k >= "1" && k <= "9" ? o.sources[Number(k) - 1] : k === "enter" ? o.sources[o.at] : null;
      if (pick) { cx.open_url(pick.url); this.overlay = null; }
      else if (k === "j" || k === "down") o.at = Math.min(o.sources.length - 1, o.at + 1);
      else if (k === "k" || k === "up") o.at = Math.max(0, o.at - 1);
    } else if (o.kind === "diff" && o.events?.length) {
      if (k === "j" || k === "down") o.at = Math.min(o.events.length - 1, o.at + 1);
      else if (k === "k" || k === "up") o.at = Math.max(0, o.at - 1);
      o.scroll.scroll_to_item(o.at, "center");
    }
    return true;
  }

  // 面の key。使った時は true
  key(e, cx) {
    const shift = e.modifiers?.shift, k = shift && e.key.length === 1 ? e.key.toUpperCase() : e.key, c = this.selected()?.item;
    const open = this.mode === "open", writes = WRITES[this.mode];
    if (k === "j" || k === "down") this.move(1, cx);
    else if (k === "k" || k === "up") this.move(-1, cx);
    else if (k === "r") this.reload(cx);
    else if (k === "/") this.type("filter", cx, "/", this.filter);
    else if (k === "D") this.diff(cx);
    else if (writes.has(k) && this.view?.running) this.owner.note = COLLECTING;
    else if (writes.has(k) && this.sec.waiting()) this.owner.note = WAITING;
    else if (k === "u") this.undo(cx);
    else if (k === "N" && open) this.type("source", cx, "N");
    else if (!c) return false;
    else if (Object.hasOwn(DECIDE, k)) this.change(cx, c, { status: open && TOGGLE.has(k) && c.status === DECIDE[k] ? "active" : DECIDE[k] });
    else if (k === "t") this.type("due", cx, "t", c.due ?? "");
    else if (k === "n") this.type("memo", cx, "n", this.notes(c) ?? "");
    else if (k === "T") this.type("title", cx, "T", c.title);
    else if (k === "f" && open) this.type("correct", cx, "f");
    else if (k === "o" || k === "enter") this.open(cx, c);
    else return false;
    return true;
  }

  // 下端の key の案内。面と、選んでいる行と、入力欄に合わせる
  hint() {
    const o = this.overlay, c = this.selected()?.item, open = this.mode === "open";
    if (this.typing === "filter") return "type to filter · ↑/↓ move · Enter keep · Esc clear";
    if (this.typing) return `${PROMPT[this.typing]} · Enter save · Esc cancel`;
    if (o?.kind === "choose") return "1-9 or j/k + Enter open · Esc cancel";
    if (o?.kind === "diff") return "j/k scroll · Esc back";
    const tail = ["D diff", "u undo", "/ filter", "r reload", "Tab face", "Esc close"];
    if (this.view?.running) return ["j/k move", "o open", "changes wait until aw-secretary finishes collecting, then r", ...tail].join(" · ");
    if (!c) return [...open ? ["N new source"] : [], ...tail].join(" · ");
    if (!open) return ["j/k move", "a active", "w waiting", "l later", "d done", "x reject", "t due", "n memo", "T title", "o open", ...tail].join(" · ");
    const toggle = k => c.status === DECIDE[k] ? `${k} active` : `${k} ${DECIDE[k]}`;
    return ["j/k move", "a adopt", "x reject", toggle("w"), toggle("l"), "d done", "t due", "n memo", "T title", "N new source", "f correct", "o open", ...tail].join(" · ");
  }

  // open の view の notes は書くたびに新しくなるので、覚えている詳細の物より先に使う
  notes(c) { return "notes" in c ? c.notes : this.details.get(c.id)?.notes; }

  // ---- 描画

  dot(t, status) {
    const d = div().size(8).flex_none().rounded(4);
    return status === "waiting" ? d.border_1().border_color(t.muted) : d.bg(t[DOT[status] ?? "border"]);
  }

  // virtual list の renderer の中では on_click 等の handler を登録できない。click は list 側の on_item_click で受ける
  line(t, r, on) {
    if (r.head) return h_flex().h(HEAD).px(8).pt(8).gap(8).items_center().text_size(11).text_color(t.dim)
      .child(div().flex_none().font_semibold().text_color(t.muted).child(r.head)).child(div().flex_none().child(String(r.n)))
      .when(r.status === "candidate", el => el.child(div().flex_1()).child(div().flex_none().child("a adopt · x reject")));
    const c = r.item;
    return h_flex().h(ROW).px(8).gap(8).items_center().rounded(6).cursor_pointer().when(on, el => el.bg(t.selected)).hover(s => s.bg(t.hover))
      .child(this.dot(t, c.status))
      .child(div().flex_1().min_w(0).truncate().child(c.title))
      .when(c.reason === "maybe_done", el => el.child(div().flex_none().text_size(11).text_color(t.done).child("✓?")))
      .child(div().flex_none().text_size(10.5).text_color(t.dim).child(badge(c.sources)))
      // 閉じた行は期限の代わりに閉じた日を出す。期限は詳細に出す
      .when(this.mode === "closed" && Boolean(c.closedAt), el => el.child(div().flex_none().text_size(11).text_color(t.dim).child(c.closedAt.slice(5, 10).replace("-", "/"))))
      .when(this.mode === "open" && Boolean(c.due), el => el.child(div().flex_none().text_size(11)
        .text_color(c.reason === "overdue" ? t.blocked : c.reason === "due_soon" ? t.working : t.dim)
        .child(`〆${c.due.slice(5).replace("-", "/")}${c.reason === "overdue" ? " overdue" : ""}`)));
  }

  field(t) {
    return v_flex().flex_none().gap(4)
      .child(div().text_size(10.5).font_semibold().text_color(t.dim).child(PROMPT[this.typing].toUpperCase()))
      .child(Input.new(this.input).h(30).px(8).rounded(7).border_1().border_color(t.accent).bg(t.background).text_size(12).text_color(t.foreground));
  }

  section(t, label, body) {
    return v_flex().flex_none().gap(2).child(div().text_size(10.5).font_semibold().text_color(t.dim).child(label)).child(body);
  }

  detail(t, c) {
    const d = c ? this.details.get(c.id) : null, notes = c && this.notes(c);
    const meta = c && [`#${c.id}`, STATUS[c.status], c.due && `〆${c.due}`, REASON[c.reason], c.closedAt && `closed ${stamp(c.closedAt)}`].filter(Boolean).join(" · ");
    // 詳細の欄は dialog の幅の 4 割で、狭い時も 320px は取る。幅と地は scroll する要素の外の枠に付ける: overflow_y_scrollbar の要素に割合の幅を付けると、中身の側にも同じ割合が掛かり、地が狭く塗られる
    // 入力欄は scroll する要素の外に置く。詳細を下まで scroll していても見える
    return v_flex().w_2_5().min_w(320).flex_none().border_l(1).border_color(t.border).bg(t.surface)
      .when(Boolean(this.typing) && this.typing !== "filter", el => el.child(this.field(t).px(14).pt(12)))
      .child(v_flex().id(`cm-${this.mode}-detail`).flex_1().min_h(0).overflow_y_scrollbar().px(14).py(12).gap(12)
        .when(!c, el => el.child(div().text_color(t.dim).child(this.view ? "No commitment selected" : "")))
        .when(Boolean(c), el => el
          .child(v_flex().flex_none().gap(4).child(div().text_size(15).font_semibold().child(c.title)).child(div().text_size(11).text_color(t.dim).child(meta)))
          .when(Boolean(c.summary), el => el.child(this.section(t, "SUMMARY", div().text_size(12.5).child(c.summary))))
          .when(Boolean(notes), el => el.child(this.section(t, "MEMO", div().text_size(12.5).child(notes))))
          .when(Boolean(c.sources.length), el => el.child(this.section(t, "SOURCES", v_flex().text_size(12.5)
            .children(c.sources.map(s => div().truncate().child(`${s.source === "github" ? "G" : "S"} ${s.label ?? s.key}`))))))
          .child(this.section(t, "HISTORY", d ? v_flex().gap(1).text_size(11.5).text_color(t.muted)
            .children((d.events ?? []).map(e => h_flex().gap(10).child(div().flex_none().text_size(10.5).text_color(t.dim).child(stamp(e.at)))
              .child(div().flex_1().min_w(0).child(e.detail ? `${e.kind}: ${e.detail}` : e.kind))))
            : div().text_size(11.5).text_color(t.dim).child("Loading…")))));
  }

  // 面の上に重ねる一覧
  layer(t) {
    const o = this.overlay;
    const box = (title, body) => div().absolute().inset_0().flex().items_center().justify_center().bg(t.popover)
      .child(v_flex().w(560).max_h(440).p(14).gap(8).rounded(8).border_1().border_color(t.border).bg(t.raised)
        .child(div().text_size(12).font_semibold().child(title)).child(body));
    if (o.kind === "choose") return box("Open which source?", v_flex().gap(2).children(o.sources.map((s, i) => h_flex().h(ROW).px(8).gap(8).items_center().rounded(6)
      .when(i === o.at, el => el.bg(t.selected)).child(div().flex_none().text_color(t.dim).child(String(i + 1)))
      .child(div().flex_1().min_w(0).truncate().child(`${s.source === "github" ? "G" : "S"} ${s.label ?? s.url}`)))));
    const events = o.events ?? [];
    return box(o.since ? `Changes since ${stamp(o.since)}` : "Changes since the last report",
      o.events === null ? div().text_color(t.dim).child("Loading…")
        : !events.length ? div().text_color(t.dim).child(o.error ?? "No changes")
        : div().h(Math.min(events.length, 14) * ROW).relative()
          .child(v_virtual_list(`cm-${this.mode}-diff`, events.length, ROW, i => `e${i}`, range => events.slice(range.start, range.end).map((e, j) => h_flex().h(ROW).px(8).gap(10).items_center().rounded(6)
            .when(range.start + j === o.at, el => el.bg(t.selected))
            .child(div().flex_none().text_size(10.5).text_color(t.dim).child(stamp(e.at)))
            .child(div().flex_none().text_size(11).text_color(t.muted).child(e.kind))
            .child(div().flex_1().min_w(0).truncate().child(`${e.title ?? ""}${e.detail ? ` · ${e.detail}` : ""}`))))
            .track_scroll(o.scroll).size_full())
          .child(Scrollbar.vertical(`cm-${this.mode}-diff`).absolute().inset_0()));
  }

  // 要素の id は面ごとに分ける。同じ id の要素は、面を移っても scroll の位置を引き継ぐ
  render(t, handle) {
    const rows = this.rows(), sel = this.selected(rows);
    const list = this.view === null ? div().p(16).text_color(t.dim).child(this.error ?? "Loading…")
      : !rows.length ? div().p(16).text_color(t.dim).child(this.filter ? "No commitment matches the filter" : this.mode === "open" ? "No open commitments" : "No commitments closed in the last 30 days")
      : div().flex_1().min_h(0).relative()
        .child(v_virtual_list(`cm-${this.mode}-list`, rows.length, rows.map(r => r.head ? HEAD : ROW), i => rows[i].key, range => rows.slice(range.start, range.end).map(r => this.line(t, r, r === sel)))
          .track_scroll(this.scroll).size_full().px(6).pb(6)
          .on_item_click((key, cx) => { const r = rows.find(r => r.key === key); if (r?.item) { this.sel = r.item.id; this.want(cx); } handle.focus(); cx.notify(); }))
        .child(Scrollbar.vertical(`cm-${this.mode}-list`).absolute().inset_0());
    // 一覧と詳細の並べ方は explorer と pr の mod に揃える。h_flex は既定で子を縦の真ん中に置き、中身の高さに縮める。items_start で真ん中に置くのをやめ、h_full で縦いっぱいにする。virtual list は高さが決まらないと描けない
    return h_flex().flex_1().min_h(0).items_start().relative()
      .child(v_flex().flex_1().min_w(0).h_full()
        .when(this.typing === "filter" || Boolean(this.filter), el => el.child(h_flex().flex_none().px(14).pt(8).gap(8).items_center()
          .child(div().flex_none().text_size(11).text_color(t.dim).child("/"))
          .child(this.typing === "filter" ? Input.new(this.input).flex_1().h(28).px(8).rounded(7).border_1().border_color(t.accent).bg(t.background).text_size(12)
            : div().flex_1().text_size(12).child(this.filter))))
        .child(list))
      .child(this.detail(t, sel?.item).h_full())
      .when(Boolean(this.overlay), el => el.child(this.layer(t)));
  }
}
