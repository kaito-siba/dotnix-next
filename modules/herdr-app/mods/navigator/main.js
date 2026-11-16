// 全ての space の pane を並べて、選んだ pane へ移る (TUI 版の session navigator に当たる)
// 文字を打つと絞り込み、ctrl-j / ctrl-k で上下、ctrl-h / ctrl-l で前後の space へ動く
// 絞り込みの文字は Input を使わずに自分で受ける。Input に keyboard を渡すと、ctrl-h や ctrl-k が Input の編集 (1 文字消す、行末まで消す) に取られ得る
// その代わり IME 越しの入力はできない
import { View, div, svg, image } from "gpui-kit";
import { v_flex, h_flex, Scrollbar, v_virtual_list, VirtualListScrollHandle } from "gpui-base";
import { spaces, panes, run, theme, home, props, closeOverlay } from "herdr";

const ROW = 30, MAX_ROWS = 16;

// agent が title の前に付ける状態の印 ("✳ ", "⠋ - ") を落とす
const clean = s => (s ?? "").replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}]+/u, "").trim();

// agent は自分で付けた title (Claude Code なら session の名前) で、他は動いている program の名前で呼ぶ
function label(p) {
  const told = p.program?.agent ? clean(p.title) : "";
  return told || p.program?.name || p.title || "shell";
}

function folder(cwd) {
  if (!cwd) return "";
  const h = home();
  return cwd === h ? "~" : cwd.startsWith(h + "/") ? "~" + cwd.slice(h.length) : cwd;
}

export default class Navigator extends View {
  init(_props, cx) {
    this.filter = "";
    // sel が null の間は、focus している pane を選ぶ
    this.sel = null;
    this.scroll = VirtualListScrollHandle.new();
    this.handle = cx.focus_handle();
    this.handle.focus();
    // 開いた直後の focus は popup の表示に奪われる事があるので、もう一度取る
    cx.timer.after(600, () => this.handle.focus());
  }

  // head が space の見出しで、他は選べる pane の行
  rows() {
    const terms = this.filter.toLowerCase().split(/\s+/).filter(Boolean);
    const all = panes().filter(p => p.terminal);
    const out = [];
    for (const space of spaces()) {
      const found = [];
      for (const tab of space.tabs) {
        for (const pane of all.filter(p => p.tab === tab.id)) {
          const name = label(pane);
          const text = [space.name, space.machine, tab.name, name, pane.program?.name, pane.cwd, pane.branch].filter(Boolean).join(" ").toLowerCase();
          if (terms.every(term => text.includes(term))) found.push({ key: pane.pane, space, tab, pane, name });
        }
      }
      if (found.length) out.push({ key: `head:${space.id}`, head: space }, ...found);
    }
    return out;
  }

  go(row) {
    if (!row) return;
    closeOverlay(props().overlay);
    run("tab.select", { id: row.tab.id });
    run("pane.focus", { pane: row.pane.pane });
  }

  select(row) {
    if (row) this.sel = row.key;
  }

  move(list, at, step) {
    this.select(list[Math.min(list.length - 1, Math.max(0, at + step))]);
  }

  // 前後の space の先頭の行へ動く。戻る時、space の途中に居たらまずその space の先頭へ
  jump(list, at, step) {
    const here = list[at];
    if (!here) return;
    const firsts = list.filter((row, i) => i === 0 || list[i - 1].space.id !== row.space.id);
    const group = firsts.findIndex(row => row.space.id === here.space.id);
    if (step < 0 && firsts[group] !== here) this.select(firsts[group]);
    else this.select(firsts[Math.min(firsts.length - 1, Math.max(0, group + step))]);
  }

  key(e, cx, list, at) {
    const m = e.modifiers ?? {}, k = e.key;
    if (m.alt || m.platform) return;
    if (k === "escape") closeOverlay(props().overlay);
    else if (k === "enter") this.go(list[at]);
    else if (k === "down" || k === "tab" && !m.shift || m.control && (k === "j" || k === "n")) this.move(list, at, 1);
    else if (k === "up" || k === "tab" || m.control && (k === "k" || k === "p")) this.move(list, at, -1);
    else if (m.control && k === "l" || k === "pagedown") this.jump(list, at, 1);
    else if (m.control && k === "h" || k === "pageup") this.jump(list, at, -1);
    else if (k === "backspace") this.type(this.filter.slice(0, -1));
    else if (m.control && k === "u") this.type("");
    else if (m.control && k === "w") this.type(this.filter.replace(/\S+\s*$/, ""));
    else if (!m.control && e.key_char && e.key_char >= " ") this.type(this.filter + e.key_char);
    // 他の key も下の端末へは流さない
    cx.stop_propagation();
    cx.notify();
  }

  // 絞り込みが変わったら、選択は先頭に戻す
  type(filter) {
    if (filter === this.filter) return;
    this.filter = filter;
    this.sel = "";
  }

  glyph(t, status) {
    if (status === "working") return svg("mods/workspace-chrome/spinner.svg").size(12).flex_none().text_color(t.working).spin(900);
    return div().w(12).flex_none().text_color(t[status] ?? t.dim).child(status === "idle" ? "○" : status ? "●" : "·");
  }

  // virtual list の renderer の中では on_click 等の handler を登録できない。click は list 側の on_item_click で受ける
  row(row, t, on) {
    if (row.head) {
      const s = row.head;
      return h_flex().h(ROW).px(10).pt(6).gap(8).items_center().text_size(11).font_semibold().text_color(t.muted)
        .child(div().flex_none().child(s.name))
        .when(Boolean(s.machine), el => el.child(div().flex_none().px(5).rounded(4).border_1().border_color(t.border).text_size(10).font_normal().text_color(t.dim).child(s.machine)))
        .when(Boolean(s.branch), el => el.child(div().min_w(0).truncate().font_normal().text_color(t.dim).child(s.branch)));
    }
    const p = row.pane, prog = p.program;
    const pic = !prog?.icon ? null : prog.tint ? svg(prog.icon).size(14).flex_none().text_color(t.muted) : image(prog.icon).w(14).h(14).flex_none();
    // tab がひとつで名前も付いていない space では、tab の番号は出さない
    const tab = row.tab.named || row.space.tabs.length > 1 ? row.tab.name : "";
    return h_flex().h(ROW).mx(4).px(10).gap(8).items_center().rounded(7).cursor_pointer()
      .when(on, el => el.bg(t.selected)).hover(s => s.bg(t.hover))
      .child(this.glyph(t, p.status))
      .when(Boolean(pic), el => el.child(pic))
      .child(div().flex_none().max_w(340).truncate().text_color(t.foreground).when(p.focused, el => el.font_semibold()).child(row.name))
      .when(p.status === "blocked", el => el.child(div().flex_none().text_size(11).text_color(t.blocked).child("needs you")))
      .when(p.status === "done", el => el.child(div().flex_none().text_size(11).text_color(t.done).child("finished")))
      .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(folder(p.cwd)))
      .when(Boolean(tab), el => el.child(div().flex_none().max_w(140).truncate().text_size(11).text_color(t.dim).child(tab)));
  }

  render() {
    const t = theme();
    const rows = this.rows(), list = rows.filter(r => !r.head);
    let at = list.findIndex(r => r.key === this.sel);
    if (at < 0) at = this.sel === null ? Math.max(0, list.findIndex(r => r.pane.focused)) : 0;
    const sel = list[at];
    // 選んだ行が見えるようにする。space の先頭の行では、見出しも一緒に見せる
    const shown = rows.indexOf(sel);
    if (sel && this.seen !== sel.key) {
      this.seen = sel.key;
      this.scroll.scroll_to_item(rows[shown - 1]?.head ? shown - 1 : shown, "center");
    }
    return v_flex().id("navigator").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx, list, at))
      .w_full().min_h(0).p(12).gap(8).bg(t.popover).text_color(t.foreground).text_size(13)
      .child(h_flex().h(34).flex_none().px(10).gap(8).items_center().rounded(9).border_1().border_color(t.accent).bg(t.background)
        .child(svg("mods/workspace-chrome/search.svg").size(15).flex_none().text_color(t.dim))
        .child(div().flex_1().min_w(0).truncate().text_color(this.filter ? t.foreground : t.dim).child(this.filter || "Go to a pane…"))
        .child(div().flex_none().text_size(11).text_color(t.dim).child(`${list.length}`)))
      .child(rows.length
        ? div().h(Math.min(rows.length, MAX_ROWS) * ROW).flex_none().relative()
          .child(v_virtual_list("nav-list", rows.length, ROW, i => rows[i].key,
            range => rows.slice(range.start, range.end).map(row => this.row(row, t, row === sel)))
            .track_scroll(this.scroll).size_full()
            .on_item_click((key, cx) => { this.go(list.find(r => r.key === key)); cx.notify(); }))
          .child(Scrollbar.vertical("nav-list").absolute().inset_0())
        : div().px(10).py(8).text_color(t.dim).child("No panes match"))
      .child(div().flex_none().px(10).text_size(11).text_color(t.dim).child("type to filter · ctrl-j/k move · ctrl-h/l space · Enter go · Esc close"));
  }
}
