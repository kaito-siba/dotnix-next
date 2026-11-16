// focus している端末の文字を、keyboard だけで選んで copy する (tmux の vi copy mode に当たる)
// app には copy mode が無く、選択を動かす command (terminal.select / terminal.adjust_selection) だけがある
// なので popup で keyboard を預かり、押された key を command に読み替える。端末は popup の下にそのまま見えている
// cursor は 1 cell の選択で表す。選択の end が cursor、start が v を押した位置になる
// 単語単位の移動 (w / b / e) と行単位の選択の伸び縮みは、相当する command が無いので作れない
import { View, div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { focused, panes, terminals, run, notify, props, closeOverlay, theme } from "herdr";

const MOVES = {
  h: "left", j: "down", k: "up", l: "right",
  left: "left", down: "down", up: "up", right: "right",
  "0": "line_start", "^": "line_start", $: "line_end",
  g: "home", G: "end",
  pageup: "page_up", pagedown: "page_down", home: "line_start", end: "line_end",
};
// 半 page の移動は無いので、ctrl-u / ctrl-d も 1 page 動かす
const CTRL_MOVES = { u: "page_up", b: "page_up", d: "page_down", f: "page_down" };

const same = (a, b) => a.row === b.row && a.col === b.col;

export default class CopyMode extends View {
  init(_props, cx) {
    this.visual = false;
    this.handle = cx.focus_handle();
    this.handle.focus();
    // popup が keyboard を持っていても、terminal の command は focus している pane の端末に届く
    if (!focused()?.terminal) {
      notify({ title: "Copy mode", body: "No focused terminal", level: "error" });
      closeOverlay(props().overlay);
      return;
    }
    // program の cursor の位置から始める
    run("terminal.select");
  }

  leave(copy) {
    if (copy) run("terminal.copy");
    run("terminal.clear_selection");
    closeOverlay(props().overlay);
  }

  // 選択中でない時に cursor が動く先。分からない移動は null
  // 行の数は pane の scroll から、alternate screen (vim 等。履歴が無い) では端末の rows から取る
  target(move, at) {
    const f = focused();
    const scroll = panes().find(p => p.pane === f?.pane)?.scroll;
    const rows = terminals().find(t => t.address === f?.terminal)?.rows;
    const last = scroll ? scroll.total - 1 : rows ? rows - 1 : null;
    const page = scroll?.len ?? rows;
    switch (move) {
      case "up": return { row: Math.max(0, at.row - 1), col: at.col };
      case "down": return last == null ? null : { row: Math.min(last, at.row + 1), col: at.col };
      case "page_up": return page ? { row: Math.max(0, at.row - page), col: at.col } : null;
      case "page_down": return page && last != null ? { row: Math.min(last, at.row + page), col: at.col } : null;
      case "home": return { row: 0, col: 0 };
      case "end": return last == null ? null : { row: last, col: 0 };
      case "line_start": return { row: at.row, col: 0 };
    }
    // 左右と行末は、全角の文字や行の折り返しで動く先が変わるので、app に任せる
    return null;
  }

  key(e, cx) {
    const m = e.modifiers ?? {};
    // shift を押した文字 (G, $, V) は key_char に入る
    const k = m.control ? e.key : (e.key_char ?? e.key);
    const sel = focused()?.selection;
    const move = m.control ? CTRL_MOVES[k] : MOVES[k];
    if (move) {
      // 選択が無くなっていたら (click で消された等)、cursor から選び直す
      if (!sel) run("terminal.select");
      else {
        // adjust_selection は選択の end だけを動かすので、選択中でなければ動いた先へ 1 cell の選択を置き直す
        // 続けて頼んだ command は間に描画を挟まず実行されるので、伸びた選択は画面に出ない
        // adjust_selection も呼ぶのは、動いた先が見えるよう scroll させるため
        const to = this.visual ? null : this.target(move, sel.end);
        if (!to || !same(to, sel.end)) run("terminal.adjust_selection", { direction: move });
        if (to && !same(to, sel.end)) run("terminal.select", { at: to });
      }
    } else if (m.control) return;
    else if (k === "v") {
      // 選択をやめる時は、cursor の位置に 1 cell だけ残す
      if (this.visual && sel) run("terminal.select", { at: sel.end });
      this.visual = !this.visual;
    } else if (k === "V") {
      // cursor の居る行を選ぶ。その後の移動は cell 単位で伸び縮みする
      if (sel) run("terminal.select", { at: sel.end, mode: "line" });
      this.visual = true;
    } else if (k === "y" || k === "enter") this.leave(this.visual);
    else if (k === "escape" && this.visual) {
      if (sel) run("terminal.select", { at: sel.end });
      this.visual = false;
    } else if (k === "escape" || k === "q") this.leave(false);
    // 他の key も端末へは流さない
    cx.stop_propagation();
    cx.notify();
  }

  render() {
    const t = theme();
    const sel = focused()?.selection;
    // 動く先が分からなかった移動は、選択が伸びた後のここ (選択が変わると描き直される) で 1 cell に戻す
    // 伸びた選択が一度描かれるので、少しちらつく
    if (!this.visual && sel && !same(sel.start, sel.end)) run("terminal.select", { at: sel.end });
    const hint = this.visual ? "y copy · esc cancel" : "hjkl 0 $ g G · v select · V line · q quit";
    return h_flex()
      .id("copy-mode")
      .track_focus(this.handle)
      .on_key_down((e, cx) => this.key(e, cx))
      .w_full()
      .h(30)
      .px(12)
      .gap(10)
      .items_center()
      .bg(t.popover)
      .text_size(12)
      .child(div().font_semibold().text_color(t.accent).child(this.visual ? "VISUAL" : "COPY"))
      .child(div().text_color(t.muted).child(sel ? `${sel.end.row + 1}:${sel.end.col + 1}` : ""))
      .child(div().flex_1())
      .child(div().text_color(t.dim).child(hint));
  }
}
