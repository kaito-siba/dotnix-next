// file を yazi のように hjkl で辿って preview する面。2 つの mod が使う (../../_app-home.nix が両方へ写す)
//   explorer  focus している pane の folder から辿る (./main.js)
//   sandbox   sbx の sandbox の中を辿る (../sandbox/main.js)
// file の取り方だけが違うので、それは source として受け取る
//   list(dir)         folder の中身: { entries } か { error }
//   read(path, max)   file の先頭 max 文字: { text } か { note }
//   fetch(path, dest) 画像を手元の dest へコピーして、できたかを返す。手元へ持って来られない source では null
import { mkdir, readFile, readdir, unlink } from "fs/promises";
import { div, image } from "gpui-kit";
import { v_flex, h_flex, Editor, EditorState, TextView, Scrollbar, v_virtual_list, VirtualListScrollHandle, InputState, Input } from "gpui-base";
import { notify, appHome, theme, settings } from "herdr";

const LANG = { ts: "js", tsx: "js", mts: "js", cts: "js", jsx: "js", mjs: "js", toml: "yaml", jsonc: "json", svelte: "html", vue: "html" };
const ROW = 28, PAD = 16, MAX_PREVIEW = 400000, MAX_ENTRIES = 5000;
const PICTURE = new Set(["png", "jpg", "jpeg", "gif", "webp"]);
// app の asset loader の上限 (16 MiB)
const MAX_PICTURE = 16 * 1024 * 1024;

// folder の中身を出す sh の script (GNU find)。$1 が folder
// 出力は "種類\tsize\tmtime\t名前\0" の繰り返し。種類は link を辿った先の物 (d が directory)
export const LIST = `cd "$1" 2>/dev/null || exit 3; find . -mindepth 1 -maxdepth 1 -printf '%Y\\t%s\\t%T@\\t%f\\0' 2>/dev/null`;

// LIST の出力を読む。folder を先に、名前の順で並べる
export function parse(stdout, dir) {
  const entries = [];
  for (const record of stdout.split("\0")) {
    const [kind, size, mtime, ...rest] = record.split("\t");
    if (!rest.length) continue;
    const file = rest.join("\t");
    entries.push({ name: file, path: join(dir, file), dir: kind === "d", size: Number(size), mtime: Number(mtime) * 1000 });
  }
  return entries.sort((a, b) => b.dir - a.dir || a.name.localeCompare(b.name));
}

export const join = (dir, name) => `${dir.replace(/\/$/, "")}/${name}`;
const parent = dir => dir.replace(/\/[^/]+\/?$/, "") || "/";

// image() は大きさを自分で決めないので、画像の header から幅と高さを読む。読めない形式は null
function measure(b) {
  const be16 = i => b[i] << 8 | b[i + 1], le16 = i => b[i] | b[i + 1] << 8, le24 = i => le16(i) | b[i + 2] << 16;
  const tag = (i, s) => [...s].every((c, n) => b[i + n] === c.charCodeAt(0));
  if (tag(1, "PNG")) return { width: be16(18), height: be16(22) };
  if (tag(0, "GIF8")) return { width: le16(6), height: le16(8) };
  if (tag(0, "RIFF") && tag(8, "WEBP")) {
    if (tag(12, "VP8 ")) return { width: le16(26) & 0x3fff, height: le16(28) & 0x3fff };
    if (tag(12, "VP8L")) return { width: 1 + (le16(21) & 0x3fff), height: 1 + (le24(22) >> 6 & 0x3fff) };
    if (tag(12, "VP8X")) return { width: 1 + le24(24), height: 1 + le24(27) };
  }
  if (b[0] === 0xff && b[1] === 0xd8) {
    // segment を順に辿って、大きさを持つ SOF (C4, C8, CC は別物) を探す
    for (let i = 2; i + 9 < b.length && b[i] === 0xff; i += 2 + be16(i + 2)) {
      const m = b[i + 1];
      if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) return { width: be16(i + 7), height: be16(i + 5) };
    }
  }
  return null;
}

export function ago(ms) {
  const s = Math.max(0, (Date.now() - ms) / 1000);
  if (s < 60) return "now";
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  // 出す所の幅は 3 文字ぶん。古い file は日数が 3 桁になるので、その前に単位を上げる
  const days = Math.floor(s / 86400);
  return days < 100 ? `${days}d` : days < 365 ? `${Math.floor(days / 7)}w` : `${Math.floor(days / 365)}y`;
}

export function bytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 ** 2) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 ** 3) return `${(n / 1024 ** 2).toFixed(1)} MB`;
  return `${(n / 1024 ** 3).toFixed(1)} GB`;
}

const drop = picture => picture ? unlink(picture.path).catch(() => {}) : null;

export class Browser {
  // id は要素の id に前置きする名前。copies は preview する画像のコピーを置く folder (app home からの相対):
  // image() は app home からの相対 path しか読めない。focus は、絞り込みの入力を閉じた時に keyboard を返す先
  constructor({ id, source, copies, dir, focus }) {
    this.id = id; this.source = source; this.copies = copies; this.focus = focus;
    this.dirs = new Map(); this.at = new Map(); this.dir = dir; this.busy = new Set();
    this.filter = ""; this.typing = false; this.hidden = false; this.raw = false; this.count = 0;
    this.shown = null; this.loaded = null; this.code = null; this.text = null; this.why = null; this.picture = null;
    this.scroll = VirtualListScrollHandle.new();
    this.input = InputState.new({ placeholder: "" });
    this.input.on("change", (_e, cx) => {
      // 入力欄を開いた key がそのまま入力される事があるので捨てる
      if (this.opening && this.input.value() === "/") { this.opening = false; this.input.set_value(""); return; }
      this.opening = false;
      if (this.typing) { this.filter = this.input.value(); this.sync(cx); cx.notify(); }
    });
    this.input.on("submit", (_e, cx) => this.type(false, cx, true));
    this.input.on("blur", (_e, cx) => { this.typing = false; cx.notify(); });
  }

  // 前に開いた時のコピーが残っている事がある (app が落ちた時など)。mod の init で 1 度呼ぶ
  static async sweep(copies) {
    const old = await readdir(`${appHome()}/${copies}`).catch(() => []);
    await Promise.all(old.map(name => drop({ path: `${appHome()}/${copies}/${name}` })));
  }

  // 使い終えた時に呼ぶ。途中の読み込みは、終わっても何も置かない
  close() {
    this.closed = true; this.shown = null;
    this.code?.release(); this.code = null;
    const picture = this.picture; this.picture = null;
    return drop(picture);
  }

  list(cx, dir, again) {
    if (!dir || this.busy.has(dir) || (!again && this.dirs.has(dir))) return;
    this.busy.add(dir);
    cx.spawn(async cx => {
      let found;
      try { found = await this.source.list(dir); }
      catch (e) { found = { error: String(e?.message ?? e) }; }
      this.busy.delete(dir);
      if (this.closed) return;
      this.dirs.set(dir, found.entries ? { entries: found.entries.slice(0, MAX_ENTRIES), more: found.entries.length > MAX_ENTRIES } : found);
      this.sync(cx);
      cx.notify();
    });
  }

  // 今の folder を読み直す
  reload(cx) { this.list(cx, this.dir, true); }

  entries(dir = this.dir) {
    const terms = dir === this.dir ? this.filter.toLowerCase().split(/\s+/).filter(Boolean) : [];
    return (this.dirs.get(dir)?.entries ?? []).filter(e => (this.hidden || !e.name.startsWith(".")) && terms.every(term => e.name.toLowerCase().includes(term)));
  }

  current() {
    const list = this.entries();
    return list.find(e => e.name === this.at.get(this.dir)) ?? list[0] ?? null;
  }

  // preview を読み終えた file が、文字として読めたか。読んでいる途中は null
  readable(entry) { return this.loaded === entry ? this.text !== null : null; }

  // 選んでいる物が変わっていたら preview を取り直す。directory なら中身を先に読んでおく
  sync(cx) {
    const e = this.current();
    if (e?.dir) this.list(cx, e.path);
    if ((e?.path ?? null) !== this.shown?.path || e?.mtime !== this.shown?.mtime) this.preview(e, cx);
  }

  enter(cx) {
    const e = this.current();
    if (!e?.dir) return;
    this.dir = e.path; this.filter = "";
    this.list(cx, this.dir, true); this.sync(cx);
  }

  leave(cx) {
    if (!this.dir || this.dir === "/") return;
    const from = this.dir;
    this.dir = parent(from); this.filter = "";
    // 戻った先では、出てきた folder を選んでおく
    this.at.set(this.dir, from.split("/").filter(Boolean).pop());
    this.list(cx, this.dir); this.sync(cx);
  }

  move(step, cx) {
    const list = this.entries(), at = list.indexOf(this.current());
    const to = list[Math.min(list.length - 1, Math.max(0, at + step))];
    if (!to) return;
    this.at.set(this.dir, to.name);
    this.scroll.scroll_to_item(list.indexOf(to), "center");
    this.sync(cx);
  }

  preview(entry, cx) {
    this.shown = entry;
    if (!entry || entry.dir) { this.code?.release(); this.code = null; this.text = null; this.why = null; drop(this.picture); this.picture = null; this.loaded = entry; return; }
    cx.spawn(async cx => {
      const ext = entry.name.includes(".") ? entry.name.split(".").pop().toLowerCase() : "txt";
      const drawn = PICTURE.has(ext) && Boolean(this.source.fetch);
      let text = null, note = null, picture = null;
      try {
        if (drawn) {
          picture = await this.copy(entry, ext);
          if (!picture) note = entry.size > MAX_PICTURE ? "Image is too large to preview" : "Cannot preview this image";
        } else {
          const r = await this.source.read(entry.path, MAX_PREVIEW + 1);
          text = r.text ?? null; note = r.note ?? null;
        }
      } catch { note = "Cannot preview this file (binary, too large, or unreadable)"; }
      if (this.closed || this.shown !== entry) { drop(picture); return; }
      if (text?.includes("\0")) { text = null; note = "Binary file · no text preview"; }
      if (text && text.length > MAX_PREVIEW) text = text.slice(0, MAX_PREVIEW) + "\n… (file truncated)";
      this.code?.release(); this.code = null; this.text = text; this.why = note;
      drop(this.picture); this.picture = picture;
      this.markdown = text !== null && (ext === "md" || ext === "markdown");
      if (text !== null) {
        const t = theme();
        this.code = EditorState.new({ language: LANG[ext] ?? ext, readonly: true, value: text, soft_wrap: this.markdown,
          font_family: settings().font_family, font_size: 12,
          syntax: { keyword: t.ansi5, string: t.ansi2, comment: t.dim, function: t.ansi4, type: t.ansi3, number: t.ansi1, constant: t.ansi6 } });
      }
      this.loaded = entry;
      cx.notify();
    });
  }

  // 同じ path の画像は描画が cache されて、中身が変わっても古いままになる。コピーは毎回違う名前にする
  async copy(entry, ext) {
    if (entry.size > MAX_PICTURE) return null;
    const name = `${this.copies}/${Date.now()}-${++this.count}.${ext}`, path = `${appHome()}/${name}`;
    await mkdir(`${appHome()}/${this.copies}`, { recursive: true });
    if (!await this.source.fetch(entry.path, path)) return null;
    const size = measure(await readFile(path));
    if (!size?.width || !size.height) { drop({ path }); return null; }
    return { name, path, ...size };
  }

  // 絞り込みの入力欄を開く、または閉じる。keep は絞り込みを残して閉じる印
  type(on, cx, keep) {
    const was = this.typing;
    this.typing = on;
    if (on) {
      this.opening = true;
      this.input.set_value(this.filter);
      this.input.focus();
    } else {
      if (was && !keep && this.filter) { this.filter = ""; this.sync(cx); }
      if (was) this.focus();
    }
    cx.notify();
  }

  // 自分の key なら受けて true を返す。入力欄に打っている間の key も true (呼んだ側は何もしない)
  // Enter は folder に入る時だけ受ける。file の上の Enter は呼んだ側が決める
  key(e, cx) {
    const m = e.modifiers ?? {};
    if (m.control || m.alt || m.platform) return false;
    const k = e.key;
    if (this.typing) {
      if (k === "escape") this.type(false, cx);
      else if (k === "down") this.move(1, cx);
      else if (k === "up") this.move(-1, cx);
      else return true;
    } else {
      const cur = this.current();
      if (k === "escape" && this.filter) { this.filter = ""; this.sync(cx); }
      else if (k === "j" || k === "down") this.move(1, cx);
      else if (k === "k" || k === "up") this.move(-1, cx);
      else if (k === "g") this.move(m.shift ? Infinity : -Infinity, cx);
      else if (k === "/") this.type(true, cx);
      else if ((k === "l" || k === "right" || k === "enter") && cur?.dir) this.enter(cx);
      else if (k === "h" || k === "left" || k === "backspace") this.leave(cx);
      else if (k === ".") { this.hidden = !this.hidden; this.sync(cx); }
      else if (k === "m") this.raw = !this.raw;
      else if (k === "y" && cur) { cx.write_to_clipboard(cur.path); notify({ title: "Files", body: `Copied ${cur.path}`, timeout: 2000 }); }
      else return false;
    }
    cx.stop_propagation();
    cx.notify();
    return true;
  }

  // 下に出す key の案内のうち、この面の分
  hint() { return `hjkl move · / filter · . hidden${this.markdown ? " · m raw" : ""} · y copy path`; }

  note(t, text) { return div().p(16).text_color(t.dim).child(text); }

  render(t) {
    const here = this.dirs.get(this.dir), list = this.entries(), cur = this.current();
    const filtering = this.typing || Boolean(this.filter), id = `${this.id}-files`;
    // virtual list の renderer の中では on_click 等の handler を登録できない。click は list 側の on_item_click で受ける
    const line = e => h_flex().h(ROW).px(8).gap(8).items_center().rounded(7).cursor_pointer().when(e === cur, el => el.bg(t.selected)).hover(s => s.bg(t.hover))
      .child(div().flex_1().min_w(0).truncate().when(e.dir, el => el.text_color(t.accent)).child(e.dir ? `${e.name}/` : e.name))
      .child(div().flex_none().text_size(11).text_color(t.dim).child(e.dir ? "" : bytes(e.size)))
      .child(div().w(26).flex_none().text_size(11).text_color(t.dim).child(ago(e.mtime)));
    return h_flex().flex_1().min_h(0).items_start()
      .child(v_flex().w(360).h_full().flex_none().border_r(1).border_color(t.border)
        .child(h_flex().h(30).flex_none().px(14).items_center().border_b(1).border_color(t.border).text_size(11).text_color(t.dim).child(div().min_w(0).truncate().child(this.dir ?? "")))
        .when(filtering, el => el.child(h_flex().flex_none().p(6).gap(8).items_center()
          .child(div().flex_none().text_size(11).text_color(t.dim).child("Filter"))
          .child(Input.new(this.input).flex_1().h(30).px(8).rounded(7).border_1().border_color(this.typing ? t.accent : t.border).bg(t.background).text_size(12).text_color(t.foreground))))
        .child(list.length
          ? div().flex_1().min_h(0).relative()
            .child(v_virtual_list(id, list.length, ROW, i => list[i].path, range => list.slice(range.start, range.end).map(line))
              .track_scroll(this.scroll).size_full().px(6)
              .on_item_click((path, cx) => {
                const e = list.find(e => e.path === path);
                if (e) { this.at.set(this.dir, e.name); this.sync(cx); }
                this.focus(); cx.notify();
              }))
            .child(Scrollbar.vertical(id).absolute().inset_0())
          : this.note(t, here?.error ?? (!here ? "Loading…" : this.filter ? "No files match the filter" : this.hidden ? "Empty folder" : "Nothing here · press . for hidden files")))
        .when(Boolean(here?.more), el => el.child(div().flex_none().px(14).py(4).text_size(11).text_color(t.dim).child(`Showing the first ${MAX_ENTRIES} entries`))))
      .child(this.pane(t, cur).h_full());
  }

  // 領域に収まる大きさで置く。元の大きさより拡げない。透過した画像は白地を前提にした物が多いので、下に白を敷く
  drawing(p) {
    const area = this.area ?? { width: 800, height: 600 };
    const scale = Math.max(0.01, Math.min((area.width - 2 * PAD) / p.width, (area.height - 2 * PAD) / p.height, 1));
    const w = Math.round(p.width * scale), h = Math.round(p.height * scale);
    return div().id(`${this.id}-picture`).flex_1().min_h(0).w_full().flex().items_center().justify_center().overflow_hidden()
      .on_size_change((size, cx) => { this.area = size; cx.notify(); })
      .child(div().w(w).h(h).flex_none().bg("#ffffff").child(image(p.name).w(w).h(h)));
  }

  pane(t, e) {
    if (!e) return v_flex().flex_1().min_w(0);
    const inner = e.dir ? this.dirs.get(e.path) : null, kids = e.dir ? this.entries(e.path) : [];
    const body = e.dir
      ? (kids.length
        ? v_flex().id(`${this.id}-kids-${e.path}`).flex_1().min_h(0).overflow_y_scrollbar().px(14).py(8).gap(2).text_size(12)
          .children(kids.slice(0, 200).map(k => div().truncate().text_color(k.dir ? t.accent : t.muted).child(k.dir ? `${k.name}/` : k.name)))
        : this.note(t, inner?.error ?? (inner ? "Empty folder" : "Loading…")))
      : this.shown?.path !== e.path ? this.note(t, "Loading file…")
      : this.picture ? this.drawing(this.picture)
      : this.code === null ? this.note(t, this.why || "Loading file…")
      : this.markdown && !this.raw ? v_flex().id(`${this.id}-markdown`).flex_1().min_h(0).overflow_y_scrollbar().px(20).py(14).text_size(13).child(TextView.markdown(`${this.id}-md-${e.path}`, this.text).selectable(true))
      : Editor.new(this.code).flex_1().min_h(0);
    return v_flex().flex_1().min_w(0).min_h(0)
      .child(h_flex().h(30).flex_none().px(14).gap(10).items_center().border_b(1).border_color(t.border).text_size(11).text_color(t.dim)
        .child(div().flex_1().min_w(0).truncate().child(e.path))
        .child(div().flex_none().child(`${e.dir ? "folder" : bytes(e.size)} · ${new Date(e.mtime).toLocaleString()}`)))
      .child(body);
  }
}
