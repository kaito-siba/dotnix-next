// focus している pane の folder から file を辿る dialog。辿り方と preview は sandbox の Files と同じ (./browser.js)
// Enter は file を開く: 文字として読める物は新しい tab の editor で、他は OS の既定の app で
// p は path を、開く前に focus していた端末の prompt に貼る
import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { spaces, panes, focused, exec, run, notify, theme, window, props, closeOverlay } from "herdr";
import { Browser, parse } from "./browser.js";

const POLL = 5000;
const EDITOR = "nvim";
// image() は app home からの相対 path しか読めないので、見せる画像はここへコピーする
const COPIES = "explorer/preview";
// 出力の形は browser.js の LIST と同じ。あちらは sandbox の中 (Linux) だけで動くが、こちらは macOS の事もある
// BSD の find には -printf が無いので、その時は 1 つずつ stat する
const LIST = `cd "$1" 2>/dev/null || exit 3
if find . -maxdepth 0 -printf '' 2>/dev/null; then
  find . -mindepth 1 -maxdepth 1 -printf '%Y\\t%s\\t%T@\\t%f\\0' 2>/dev/null
else
  for p in * .[!.]* ..?*; do
    [ -e "$p" ] || [ -L "$p" ] || continue
    if [ -d "$p" ]; then k=d; else k=f; fi
    printf '%s\\t%s\\t%s\\0' "$k" "$(stat -f '%z%t%m' "$p" 2>/dev/null || printf '0\\t0')" "$p"
  done
fi`;
// 開いた app が、dialog を閉じた時に道連れにならないよう切り離す。$1 が開く command、$2 が file
const OPEN = `nohup "$1" "$2" >/dev/null 2>&1 &`;

function location() {
  const space = spaces().find(s => s.active), f = focused();
  const pane = f?.pane ? panes().find(p => p.pane === f.pane) : null;
  return { cwd: pane?.cwd || f?.cwd || space?.folder, on: space?.machine ?? null };
}

const last = text => text.trim().split("\n").pop();

export default class Explorer extends View {
  init(_props, cx) {
    this.loc = location();
    const on = this.loc.on;
    this.handle = cx.focus_handle();
    this.browser = new Browser({
      id: "ex", copies: COPIES, dir: this.loc.cwd ?? "/", focus: () => this.handle.focus(),
      source: {
        list: async dir => {
          const r = await exec("sh", ["-c", LIST, "ls", dir], { on });
          return r.code === 0 ? { entries: parse(r.stdout, dir) } : { error: r.code === 3 ? "Cannot open this folder" : last(r.stderr) || "Cannot list this folder" };
        },
        read: async (path, max) => {
          const r = await exec("head", ["-c", String(max), path], { on });
          return r.code === 0 ? { text: r.stdout } : { note: last(r.stderr) || "Cannot read this file" };
        },
        // 他の machine の file は app home へコピーできないので、画像としては出さない
        fetch: on ? null : async (path, dest) => (await exec("cp", [path, dest])).code === 0,
      },
    });
    this.handle.focus();
    // 開いた直後の focus は dialog の表示に奪われる事があるので、もう一度取る
    cx.timer.after(600, () => this.handle.focus());
    cx.timer.every(POLL, cx => this.browser.reload(cx));
    cx.spawn(async cx => { await Browser.sweep(COPIES); this.browser.reload(cx); });
  }

  async close() { await this.browser.close(); }

  // preview が文字として読めた file は、その folder で editor を新しい tab に開く。他は OS の既定の app に渡す
  // 既定の app に渡すと、文字の file は端末の外の editor に行ってしまう
  open(cx) {
    const e = this.browser.current(), text = e && !e.dir ? this.browser.readable(e) : null;
    // preview を読んでいる途中は、どちらで開くか決まらない
    if (text === null) return;
    if (text) {
      closeOverlay(props().overlay);
      run("tab.new", { folder: this.browser.dir, argv: [EDITOR, e.path] });
    } else if (this.loc.on) {
      notify({ title: "Files", body: `${e.name} is on ${this.loc.on} · only text files open from another machine`, level: "warning" });
    } else {
      cx.spawn(async () => {
        const r = await exec("sh", ["-c", OPEN, "open", window()?.platform === "macos" ? "open" : "xdg-open", e.path]).catch(error => ({ code: 1, stderr: String(error?.message ?? error) }));
        if (r.code !== 0) notify({ title: "Files", body: last(r.stderr) || `Cannot open ${e.name}`, level: "error" });
      });
    }
  }

  // path を、開く前に focus していた端末の prompt に貼って閉じる。改行は送らないので、続けて指示を書ける
  // 貼るのは clipboard 越し (terminal.paste) なので、clipboard は path で上書きされる
  paste(cx) {
    const e = this.browser.current();
    if (!e) return;
    const f = focused(), pane = f?.pane ? panes().find(p => p.pane === f.pane) : null;
    if (!pane?.terminal) { notify({ title: "Files", body: "Focus a terminal pane first, then paste again", level: "warning" }); return; }
    cx.write_to_clipboard(`${e.path} `);
    run("terminal.paste");
    closeOverlay(props().overlay);
    run("pane.focus", { pane: pane.pane });
  }

  key(e, cx) {
    if (e.modifiers.control || e.modifiers.alt || e.modifiers.platform) return;
    if (this.browser.key(e, cx)) return;
    const k = e.key;
    if (k === "escape" || k === "q") closeOverlay(props().overlay);
    else if (k === "r") this.browser.reload(cx);
    else if (k === "enter") this.open(cx);
    else if (k === "p") this.paste(cx);
    else return;
    cx.stop_propagation();
    cx.notify();
  }

  render() {
    const t = theme();
    // dialog の枠は角丸だが、中身は角丸に切り抜かれない。背景も同じ丸みにして、角からはみ出させない
    return v_flex().id("explorer").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .size_full().min_h(0).rounded(10).bg(t.popover).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(10).items_center().border_b(1).border_color(t.border)
        .child(div().flex_none().font_semibold().child("Files"))
        .when(Boolean(this.loc.on), el => el.child(div().flex_none().px(5).rounded(4).border_1().border_color(t.border).text_size(10).text_color(t.dim).child(this.loc.on)))
        .child(div().flex_1())
        .child(div().min_w(0).truncate().text_size(11).text_color(t.dim).child(`${this.browser.hint()} · Enter open · p paste path · r reload · q close`)))
      .child(this.browser.render(t));
  }
}
