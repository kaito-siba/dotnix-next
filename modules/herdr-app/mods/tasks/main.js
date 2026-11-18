// focus している agent の session が何をしているかを出す右 panel。左バーの Agents (../cheki-agents) と同じ色と字で描く
// 中身は task-notes が turn の後に書く記録 (../../task-notes)。agent の動く machine の $XDG_STATE_HOME/task-notes/<session id>.json にある
// agent の居ない pane (zsh など) へ focus が移っても、前に追っていた agent を出し続ける
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { spaces, agents, focused, theme, run, exec, layout } from "herdr";
import { where } from "./where.js";
// 色と字と状態の印は、左バーの Agents と分け合う (nix がコピーする)
import { ROUND, palette, WORD, tone, clock, initials, mark } from "./lycoreco.js";

const POLL = 15000;
// 記録と、失敗と、書いている途中の印を 1 度に読む。途中の印は、落ちた summarize が残した古い物を数えない
const SEP = "\u001e";
const READ = `d="\${XDG_STATE_HOME:-$HOME/.local/state}/task-notes"
cat "$d/$1.json" 2>/dev/null; printf '\\036'
cat "$d/$1.error" 2>/dev/null; printf '\\036'
find "$d" -maxdepth 1 -name "$1.running" -mmin -5 2>/dev/null | grep -q . && echo running`;
const KIND = { decision: ["DECIDED", "accent"], assumption: ["ASSUMED", "run"], you_said: ["YOU SAID", "done"] };
// DECISIONS と LOG は新しい方からこれだけ出し、残りは畳む
const DECIDED = 6, LOG = 4;

// agent が title の前に付ける状態の印 ("✳ ", "⠋ - ") を落とす。task-notes の clean と同じ
const clean = s => (s ?? "").replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}]+/u, "").trim();

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) { const found = find(child, id); if (found) return found; }
  return null;
}

const parse = text => { try { return text.trim() ? JSON.parse(text) : null; } catch { return null; } };

export default class Tasks extends View {
  init(_props, cx) {
    // follow は追っている agent の address。note は記録、error は失敗、place は where で訊いた session と branch
    this.follow = null; this.note = null; this.error = null; this.writing = false; this.place = null;
    this.loaded = false; this.busy = false; this.open = new Set();
    // 隠れている間も timer は回るので、見えている時だけ取り直す
    cx.timer.every(POLL, cx => { if (this.visible()) this.load(cx); });
  }

  visible() {
    const root = layout(), panel = find(root, "panel"), body = find(root, "panel-body");
    return Boolean(panel) && !panel.hidden && body?.active === "tasks";
  }

  // focus している端末が agent ならそれに乗り換える。agent でない所への focus では動かない
  // focused().agent は見ない: focus と別に持たれる「agent の block が出す agent」で、agent でない pane に focus しても他の agent を指す
  track() {
    const f = focused(), list = agents();
    const here = list.find(a => a.address === (f?.shown ?? f?.terminal));
    if (here && here.address !== this.follow) {
      this.follow = here.address;
      this.note = null; this.error = null; this.writing = false; this.place = null; this.loaded = false; this.open.clear();
    }
    return this.follow ? list.find(a => a.address === this.follow) ?? null : null;
  }

  load(cx) {
    const address = this.follow;
    if (!address || this.busy) return;
    this.busy = true;
    // 他の machine の agent は "<machine>/t7"
    const on = address.includes("/") ? address.split("/")[0] : null;
    cx.spawn(async cx => {
      try {
        // session は /clear で変わるので、毎回訊く
        const place = await where({ terminal: address, on });
        if (address !== this.follow) return;
        this.place = place;
        if (!place.session) { this.note = null; this.error = null; this.writing = false; return; }
        const out = await exec("sh", ["-c", READ, "read", place.session], { on }).catch(() => null);
        if (address !== this.follow) return;
        const [note = "", error = "", writing = ""] = (out?.stdout ?? "").split(SEP);
        this.note = parse(note); this.error = parse(error); this.writing = writing.trim() === "running";
      } finally {
        if (address === this.follow) this.loaded = true;
        this.busy = false;
        cx.notify();
      }
    });
  }

  render(cx) {
    const t = theme(), c = palette(t);
    const agent = this.track();
    if (this.visible() && this.follow && !this.loaded) this.load(cx);
    const n = this.note, now = Date.now();
    // 失敗は、それより後に書けていれば出さない
    const failed = this.error && (!n || this.error.at > n.updatedAt) ? this.error : null;

    return v_flex().id("tasks").size_full().min_h(0).relative().rounded(10).overflow_hidden().bg(t.chrome).border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(svg("mods/cheki-agents/dots.svg").absolute().top(0).left(0).w(640).h(2400).text_color(c.dots))
      .child(h_flex().flex_none().pl(14).pr(12).pt(14).pb(9).gap(8).items_center()
        .child(div().font_family(ROUND).text_size(11).font_weight(800).text_color(c.accent).child("TASK"))
        .child(div().flex_1())
        .when(this.writing, el => el.child(this.pill(c.run, c.runBg, "WRITING", svg("mods/workspace-chrome/spinner.svg").size(9).flex_none().spin(900))))
        .when(Boolean(n), el => el.child(div().flex_none().font_family(ROUND).text_size(10).font_weight(700).text_color(t.dim)
          .child(`T${n.turns} · ${clock(now - n.updatedAt)}`))))
      .child(!this.follow ? this.empty(t, "Focus an agent's pane to follow what it's doing.")
        : v_flex().flex_1().min_h(0)
          .child(this.card(t, c, agent))
          .child(v_flex().id("tasks-body").flex_1().min_h(0).overflow_y_scrollbar().px(14).pt(12).pb(16).gap(16)
            .when(Boolean(failed), el => el.child(this.failure(t, c, failed, now)))
            .children(this.body(t, c, n, now))));
  }

  pill(ink, bg, text, icon) {
    return h_flex().flex_none().items_center().gap(4).px(6).rounded(7).bg(bg).text_color(ink).font_family(ROUND).text_size(9.5).font_weight(700).line_height("15px")
      .when(Boolean(icon), el => el.child(icon)).child(text);
  }

  empty(t, text) {
    return div().px(14).pt(6).text_size(12).line_height("18px").text_color(t.dim).child(text);
  }

  // 追っている agent。左バーの focus している行と同じ形で、押すとその pane へ移る
  card(t, c, a) {
    const p = this.place, n = this.note;
    const name = (a?.program?.agent ? clean(a.title) : "") || n?.title || a?.program?.name || "agent";
    const space = a ? spaces().find(s => s.id === a.space) : null;
    const code = a ? `${initials(a.space_name)}-${(space?.tabs.findIndex(tab => tab.id === a.tab) ?? -1) + 1 || "?"}` : null;
    const [ink] = tone(c, a?.status);
    const branch = p?.branch ?? n?.branch;
    return v_flex().id("tk-agent").flex_none().mx(8).px(8).pt(6).pb(7).gap(4).rounded(12).border(1.5)
      .border_color(a?.focused ? c.accent : `${c.accent}00`)
      .bg(a?.status === "blocked" ? c.callBg : c.onBg)
      .when(Boolean(a), el => el.cursor_pointer().hover(s => s.bg(t.hover)).on_click(() => run("pane.focus", { pane: a.pane })))
      .child(div().truncate().text_size(12.5).font_weight(600).child(name))
      .child(h_flex().items_center().gap(7)
        .when(Boolean(code), el => el.child(this.pill(c.accent, c.accentBg, code)))
        .child(a ? h_flex().flex_none().items_center().gap(4).font_family(ROUND).text_size(9.5).font_weight(800).text_color(ink).child(mark(a.status, ink)).child(WORD[a.status] ?? a.status.toUpperCase())
          : div().font_family(ROUND).text_size(9.5).font_weight(800).text_color(t.dim).child("CLOSED"))
        .when(Boolean(branch), el => el.child(div().flex_1().min_w(0).truncate().text_size(10.5).text_color(t.dim).child(branch))));
  }

  failure(t, c, e, now) {
    return v_flex().flex_none().px(10).py(8).gap(3).rounded(12).bg(c.callBg)
      .child(h_flex().items_center().gap(6).font_family(ROUND).text_size(9.5).font_weight(800).text_color(c.call)
        .child("SUMMARY FAILED").child(div().flex_1()).child(div().text_color(t.dim).font_weight(700).child(clock(now - e.at))))
      .child(div().text_size(11.5).line_height("16px").text_color(t.muted).child(e.message || "unknown error"));
  }

  // 見出しと点線。左バーの区切りと同じ形
  section(t, c, label, right) {
    return h_flex().gap(6).items_center()
      .child(div().flex_none().font_family(ROUND).text_size(9.5).font_weight(800).text_color(c.accent).child(label))
      .child(div().flex_1().border_t(1.5).border_dashed().border_color(t.border))
      .when(Boolean(right), el => el.child(right));
  }

  // 畳んだ物を開く小さな押し口
  toggle(t, key, text) {
    const open = this.open.has(key);
    return h_flex().id(`tk-${key}`).flex_none().items_center().gap(3).text_size(10.5).text_color(t.dim).cursor_pointer()
      .hover(s => s.text_color(t.foreground))
      .on_click((_e, cx) => { open ? this.open.delete(key) : this.open.add(key); cx.notify(); })
      .child(svg(`mods/workspace-chrome/chevron-${open ? "down" : "right"}.svg`).size(10).flex_none())
      .child(text);
  }

  body(t, c, n, now) {
    const p = this.place;
    if (!this.loaded) return [this.empty(t, "Loading…")];
    if (!p?.session) return [this.empty(t, p?.source === "sbx"
      ? "Can't tell which session in the sandbox this is yet. It shows up after the agent's next turn."
      : "Only Claude Code sessions are summarized.")];
    if (!n) return [this.empty(t, this.writing ? "Writing the first summary…" : "No summary yet. It appears after the agent's next turn.")];

    const text = (s, color) => div().flex_1().min_w(0).text_size(12.5).line_height("18px").text_color(color ?? t.foreground).child(s);
    const turn = k => div().flex_none().font_family(ROUND).text_size(9.5).font_weight(700).text_color(t.dim).child(`T${k}`);
    const out = [];

    // goal は動いた時だけ、その turn ときっかけを添える。前の goal は畳む
    const goals = n.goals ?? [], goal = goals[goals.length - 1];
    if (goal) {
      const before = goals.slice(0, -1);
      out.push(v_flex().gap(6)
        .child(this.section(t, c, "GOAL"))
        .child(div().text_size(13.5).font_weight(600).line_height("20px").child(goal.text))
        .when(before.length > 0, el => el
          .child(h_flex().gap(6).items_start()
            .child(this.pill(c.idle, c.idleBg, `T${goal.turn} CHANGED`))
            .child(text(goal.because || "", t.muted)))
          .child(this.toggle(t, "goals", `${before.length} earlier goal${before.length === 1 ? "" : "s"}`))
          .when(this.open.has("goals"), el => el.children(before.map(g => h_flex().gap(8).items_start()
            .child(turn(g.turn)).child(text(g.text, t.dim)))))));
    }

    if (n.steps?.length) {
      const icon = st => st === "done" ? svg("mods/workspace-chrome/check.svg").size(11).flex_none().mt(3).text_color(c.done)
        : st === "now" ? svg("mods/workspace-chrome/spinner.svg").size(11).flex_none().mt(3).text_color(c.run).spin(900)
        : div().size(8).mx(1.5).mt(5).flex_none().rounded(4).border(1.5).border_color(c.idle);
      out.push(v_flex().gap(5)
        .child(this.section(t, c, "PLAN", n.planFile ? div().flex_none().max_w(160).truncate().text_size(10.5).text_color(c.accent).child(n.planFile.split("/").pop()) : null))
        .children(n.steps.map(st => h_flex().gap(8).items_start()
          .child(icon(st.state))
          .child(text(st.text, st.state === "done" ? t.muted : st.state === "now" ? t.foreground : t.dim)))));
    }

    if (n.notDone?.length) {
      out.push(v_flex().gap(5)
        .child(this.section(t, c, "LEFT OPEN"))
        .children(n.notDone.map(s => h_flex().gap(8).items_start()
          .child(div().w(12).flex_none().font_family(ROUND).font_weight(800).text_color(c.call).child("!"))
          .child(text(s)))));
    }

    const decisions = n.decisions ?? [];
    // 新しい方から。決定は turn ごとに増えていくので、古い方は畳む
    const live = decisions.filter(d => !d.superseded).reverse(), gone = decisions.filter(d => d.superseded).reverse();
    if (decisions.length) {
      const item = (d, dead) => {
        const [word, key] = KIND[d.kind] ?? [d.kind.toUpperCase(), "idle"];
        return h_flex().gap(8).items_start()
          .child(div().flex_none().mt(1).when(dead, el => el.opacity(0.5)).child(this.pill(c[key], c[`${key}Bg`], word)))
          .child(div().flex_1().min_w(0).text_size(12).line_height("17px").text_color(dead ? t.dim : t.foreground).when(dead, el => el.line_through()).child(d.text))
          .child(div().mt(1).child(turn(dead ? `${d.turn}→${d.superseded}` : d.turn)));
      };
      out.push(v_flex().gap(7)
        .child(this.section(t, c, "DECISIONS"))
        .children((this.open.has("decided") ? live : live.slice(0, DECIDED)).map(d => item(d, false)))
        .when(live.length > DECIDED, el => el.child(this.toggle(t, "decided", this.open.has("decided") ? "Show fewer" : `${live.length - DECIDED} older`)))
        .when(gone.length > 0, el => el
          .child(this.toggle(t, "gone", `${gone.length} overturned`))
          .when(this.open.has("gone"), el => el.children(gone.map(d => item(d, true))))));
    }

    // 経緯は新しい方から。古い方は畳む
    const log = [...(n.timeline ?? [])].reverse();
    if (log.length) {
      const shown = this.open.has("log") ? log : log.slice(0, LOG);
      out.push(v_flex().gap(6)
        .child(this.section(t, c, "LOG"))
        .children(shown.map(e => h_flex().gap(8).items_start()
          .child(div().w(30).flex_none().mt(1).child(turn(e.turn)))
          .child(text(e.text, t.muted))
          .child(div().flex_none().mt(1).font_family(ROUND).text_size(9.5).font_weight(700).text_color(t.dim).child(clock(now - e.at)))))
        .when(log.length > LOG, el => el.child(this.toggle(t, "log", this.open.has("log") ? "Show fewer" : `${log.length - LOG} older`))));
    }
    return out;
  }
}
