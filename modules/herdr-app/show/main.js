// Show: セッションの横に、エージェントが `show <file>` で送ってきた物を並べる
// パネル。画像は開いて注釈 (ペン / 矢印 / 文字) を描き、焼き込んだコピーを
// 保存したり、そのパスを端末の prompt に貼り戻したりできる。
//
// 同じ mod を 2 通りに使う: layout の block としては一覧、props().mark 付きの
// dialog としては注釈画面。物の置き場と焼き込みは `show` コマンド (./env.js の
// SHOW) が受け持ち、mod はそれを呼ぶだけ。
import { View, div, svg, image } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { exec, appHome, spaces, panes, focused, run, theme, props, openOverlay, closeOverlay, notify, watchFolder, shared, setShared, window } from "herdr";
import { SHOW } from "./env.js";

const MOD = "show";
// image() は app home からの相対パスしか読めない。
const ITEMS = "show/items";
// app の asset loader の上限 (16 MiB)。超える物は preview を出さない。
const MAX_PREVIEW = 16 * 1024 * 1024;
const COLORS = ["#ff3b30", "#ffcc00", "#34c759", "#0a84ff", "#ffffff"];
const TOOLBAR = 48, PAD = 16;

const clock = (time) => {
  const d = new Date(time * 1000), two = (n) => String(n).padStart(2, "0");
  return `${two(d.getHours())}:${two(d.getMinutes())}`;
};
const minute = (item) => Math.floor((item.batch ?? item.time) / 60);
const previewable = (item) => Boolean(item.width && item.height) && item.size <= MAX_PREVIEW;
const absolute = (item) => `${appHome()}/${ITEMS}/${item.file}`;
const clamp = (n) => Math.min(1, Math.max(0, n));
const round = (n) => Math.round(n * 10000) / 10000;
const fail = (e) => notify({ title: "Show", body: String(e?.message ?? e), level: "error" });
// ファイルを既定の app で開くコマンドは OS で違う。
const opener = () => (window()?.platform === "macos" ? "open" : "xdg-open");

async function show(args) {
  const r = await exec(SHOW, args);
  if (r.code !== 0) throw new Error(r.stderr.trim() || `show ${args[0]} failed`);
  return r.stdout;
}

// パスを focus 中の端末に貼る。改行は送らないので、続けて指示を書ける。
// Claude Code は貼られた画像のパスを [Image #n] として取り込む。
function paste(path, cx) {
  const f = focused();
  const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
  if (!pane?.terminal) {
    notify({ title: "Show", body: "Focus a terminal pane first, then send again", level: "warning" });
    return null;
  }
  if (pane.terminal.includes("/")) {
    notify({ title: "Show", body: "The file is on this computer; a terminal on another machine can't read it", level: "warning" });
    return null;
  }
  cx.write_to_clipboard(`${path} `);
  run("terminal.paste");
  return pane.pane;
}

// 2 点の間を丸い点で埋めて線にする。座標は表示 px。
function stroke(out, a, b, width, color) {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  const steps = Math.max(1, Math.ceil(Math.hypot(dx, dy) / Math.max(1, width / 2)));
  for (let i = 0; i <= steps; i++) {
    const x = a[0] + (dx * i) / steps, y = a[1] + (dy * i) / steps;
    out.push(div().absolute().left(x - width / 2).top(y - width / 2).size(width).rounded(width / 2).bg(color));
  }
}

// 矢じりの 2 点。show.sh の焼き込みと同じ式 (25 度)。
function arrowHead(a, b, width) {
  const dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy);
  if (len < 1) return null;
  const head = Math.max(width * 6, 18), ux = dx / len, uy = dy / len, cos = 0.9063, sin = 0.4226;
  return [
    [b[0] - head * (ux * cos - uy * sin), b[1] - head * (uy * cos + ux * sin)],
    [b[0] - head * (ux * cos + uy * sin), b[1] - head * (uy * cos - ux * sin)],
  ];
}

export default class Show extends View {
  init(_props, cx) {
    this.mark = props()?.mark ?? null;
    this.size = null;
    if (this.mark) this.initMark();
    else this.initList(cx);
  }

  render(cx) {
    return this.mark ? this.renderMark() : this.renderList(cx);
  }

  // ---- 一覧 ----

  initList(cx) {
    this.items = [];
    this.error = null;
    this.loading = false;
    this.again = false;
    this.batch = null;
    this.scope = localStorage.getItem("scope") === "all" ? "all" : "here";
    this.rev = shared("show.rev");
    this.refresh(cx);
    // 監視が張れなかった時 (置き場が無い、ディレクトリが多すぎる) の保険。
    cx.timer.every(15000, (cx) => this.refresh(cx));
    cx.spawn(async (cx) => {
      try {
        const dir = (await show(["--dir"])).trim();
        for (;;) { await watchFolder(dir); this.refresh(cx); }
      } catch { /* timer が拾う */ }
    });
  }

  refresh(cx) {
    // 書き込みの途中で通知が続けて来るので、読んでいる最中の分は読み直しに回す。
    if (this.loading) { this.again = true; return; }
    this.loading = true;
    cx.spawn(async (cx) => {
      try {
        do {
          this.again = false;
          this.items = JSON.parse((await show(["--list"])) || "[]");
          this.error = null;
        } while (this.again);
      } catch (e) { this.error = String(e?.message ?? e); }
      finally { this.loading = false; cx.notify(); }
    });
  }

  // 今の space の端末がいるフォルダと、送られた時の cwd が親子ならその space の物。
  here(space) {
    const tabs = new Set((space?.tabs ?? []).map((tab) => tab.id));
    const folders = panes().filter((p) => tabs.has(p.tab) && p.cwd).map((p) => p.cwd);
    if (space?.folder) folders.push(space.folder);
    return (item) => folders.some((f) => item.cwd === f || item.cwd.startsWith(`${f}/`) || f.startsWith(`${item.cwd}/`));
  }

  // 元の物を古い順に、注釈付きコピーはそれぞれ元のすぐ下に。
  ordered(items) {
    const ids = new Set(items.map((i) => i.id));
    const out = [];
    for (const item of items) {
      if (item.parent && ids.has(item.parent)) continue;
      out.push(item, ...items.filter((child) => child.parent === item.id));
    }
    return out;
  }

  open(item) {
    openOverlay({ mod: MOD, kind: "dialog", width: 0.9, height: 0.9, props: { mark: item } });
  }

  remove(item, cx) {
    cx.spawn(async (cx) => {
      try { await show(["--rm", item.id]); } catch (e) { fail(e); }
      this.refresh(cx);
    });
  }

  row(item, width, t) {
    const scale = previewable(item) ? Math.min(width / item.width, (width * 1.5) / item.height, 1) : 0;
    const w = Math.round(item.width * scale), h = Math.round(item.height * scale);
    const action = (id, child, click) => div().id(`${id}-${item.id}`).size(22).flex_none().flex().items_center().justify_center().rounded(5)
      .text_color(t.dim).cursor_pointer().hover((s) => s.bg(t.hover).text_color(t.foreground)).on_click(click).child(child);
    return v_flex().flex_none().gap(4)
      .child(h_flex().h(24).gap(6).items_center()
        .child(svg("mods/files/file.svg").size(12).flex_none().text_color(item.parent ? t.accent : t.dim))
        .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(item.name))
        .child(div().flex_none().text_size(11).text_color(t.dim).child(clock(item.time)))
        .child(action("send", svg("mods/show/send.svg").size(14), (_e, cx) => {
          const pane = paste(absolute(item), cx);
          if (pane) run("pane.focus", { pane });
        }))
        .child(action("remove", svg("mods/pane/close.svg").size(11), (_e, cx) => this.remove(item, cx))))
      .child(scale > 0
        ? div().id(`open-${item.id}`).w(w).h(h).flex_none().rounded(8).overflow_hidden().border_1().border_color(t.border).cursor_pointer()
          .hover((s) => s.border_color(t.accent)).on_click(() => this.open(item))
          .child(image(`${ITEMS}/${item.file}`).w(w).h(h))
        : div().px(10).py(8).rounded(8).border_1().border_color(t.border).text_size(11.5).text_color(t.dim)
          .child(item.src ?? "No preview"));
  }

  renderList(cx) {
    const rev = shared("show.rev");
    if (rev !== this.rev) { this.rev = rev; this.refresh(cx); }

    const t = theme();
    const space = spaces().find((s) => s.active);
    const scoped = this.scope === "all" ? this.items : this.items.filter(this.here(space));
    const batches = [...new Map(scoped.filter((i) => !i.parent).map((i) => [minute(i), i])).entries()];
    if (this.batch !== null && !batches.some(([key]) => key === this.batch)) this.batch = null;
    const list = this.ordered(this.batch === null ? scoped : scoped.filter((i) => minute(i) === this.batch));
    const width = Math.max(120, (this.size?.width ?? 368) - 2 * 12 - 2);

    const pill = (id, label, on, click) => div().id(id).h(22).px(8).flex_none().flex().items_center().rounded(6).text_size(11.5)
      .bg(on ? t.selected : t.background).text_color(on ? t.foreground : t.dim).cursor_pointer()
      .hover((s) => s.bg(t.hover)).on_click(click).child(label);
    const scope = (name, label) => pill(`scope-${name}`, label, this.scope === name, (_e, cx) => {
      this.scope = name;
      localStorage.setItem("scope", name);
      cx.notify();
    });

    return v_flex().id("show").size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background).border_1().border_color(t.border)
      .text_color(t.foreground).text_size(13)
      .on_size_change((size, cx) => { this.size = size; cx.notify(); })
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().child("Show"))
        .child(div().flex_1().min_w(0).truncate().text_size(12).text_color(t.dim).child(this.scope === "all" ? "everything" : space?.name ?? ""))
        .child(scope("here", "Here"))
        .child(scope("all", "All")))
      .when(batches.length > 1, (el) => el.child(h_flex().id("show-batches").h(34).flex_none().px(12).gap(4).items_center().overflow_x_scrollbar()
        .children(batches.map(([key, item]) => pill(`batch-${key}`, clock(item.batch ?? item.time), this.batch === key, (_e, cx) => {
          this.batch = this.batch === key ? null : key;
          cx.notify();
        })))))
      .child(v_flex().id("show-list").flex_1().min_h(0).overflow_y_scrollbar().p(12).gap(12)
        .children(list.map((item) => this.row(item, width, t)))
        .when(list.length === 0, (el) => el.child(v_flex().gap(6).text_size(12).text_color(t.dim)
          .child(this.error ?? (this.loading ? "Loading…" : "Nothing here yet"))
          .when(!this.error && !this.loading, (el) => el.child("Run `show <file>` in a terminal, or ask the agent to, and it lands here.")))));
  }

  // ---- 注釈 ----

  initMark() {
    this.shapes = [];
    this.drawing = null;
    this.tool = "pen";
    this.color = COLORS[0];
    this.busy = false;
    this.note = InputState.new({ placeholder: "Note text, then click the image" });
  }

  dismiss() {
    closeOverlay(props()?.overlay);
  }

  // 表示サイズに依らないよう、要素内の位置を 0..1 にして持つ。
  point(e, w, h) {
    const at = e.local_position;
    if (!at) return null;
    return [round(clamp(at.x / (e.bounds?.width || w))), round(clamp(at.y / (e.bounds?.height || h)))];
  }

  press(e, w, h, cx) {
    cx.stop_propagation();
    const at = this.point(e, w, h);
    if (!at || this.busy) return;
    if (this.tool === "text") {
      const text = this.note.value().trim();
      if (!text) { notify({ title: "Show", body: "Type the note first, then click where it goes", level: "info" }); return; }
      this.shapes.push({ type: "text", color: this.color, size: round(20 / w), at, text });
    } else if (this.tool === "arrow") {
      this.drawing = { type: "arrow", color: this.color, stroke: round(4 / w), from: at, to: at };
      this.shapes.push(this.drawing);
    } else {
      this.drawing = { type: "pen", color: this.color, stroke: round(4 / w), points: [at] };
      this.shapes.push(this.drawing);
    }
    cx.notify();
  }

  drag(e, w, h, cx) {
    const at = this.drawing && this.point(e, w, h);
    if (!at) return;
    if (this.drawing.type === "arrow") this.drawing.to = at;
    else {
      // 2px 未満の動きは捨てる: 点が増えると描画も焼き込みの引数も重くなる。
      const last = this.drawing.points[this.drawing.points.length - 1];
      if (Math.hypot((at[0] - last[0]) * w, (at[1] - last[1]) * h) < 2) return;
      this.drawing.points.push(at);
    }
    cx.notify();
  }

  release(cx) {
    if (!this.drawing) return;
    // 動かさずに離した矢印は何も指していない。
    const d = this.drawing;
    if (d.type === "arrow" && d.from[0] === d.to[0] && d.from[1] === d.to[1]) this.shapes.pop();
    this.drawing = null;
    cx.notify();
  }

  marks(w, h) {
    const out = [], px = (p) => [p[0] * w, p[1] * h];
    for (const shape of this.shapes) {
      const width = Math.max(2, (shape.stroke ?? 0) * w);
      if (shape.type === "text") {
        out.push(div().absolute().left(shape.at[0] * w).top(shape.at[1] * h).text_size(Math.max(9, shape.size * w))
          .font_semibold().text_color(shape.color).child(shape.text));
      } else if (shape.type === "arrow") {
        const a = px(shape.from), b = px(shape.to), head = arrowHead(a, b, width);
        stroke(out, a, b, width, shape.color);
        if (head) { stroke(out, head[0], b, width, shape.color); stroke(out, head[1], b, width, shape.color); }
      } else {
        const points = shape.points.map(px);
        if (points.length === 1) stroke(out, points[0], points[0], width, shape.color);
        for (let i = 1; i < points.length; i++) stroke(out, points[i - 1], points[i], width, shape.color);
      }
    }
    return out;
  }

  // 注釈を焼いたコピーを作り、出来た物を then に渡す。
  bake(cx, then) {
    if (this.busy) return;
    const marks = JSON.stringify({ shapes: this.shapes });
    // 1 つの引数で渡すので、Linux の上限 (128 KiB) の手前で止める。
    if (marks.length > 100000) { notify({ title: "Show", body: "Too many marks to save; undo some strokes", level: "warning" }); return; }
    this.busy = true;
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const made = JSON.parse(await show(["--bake", this.mark.id, marks]));
        setShared("show.rev", Date.now());
        then(made, cx);
      } catch (e) { fail(e); }
      finally { this.busy = false; cx.notify(); }
    });
  }

  save(cx) {
    if (this.shapes.length === 0) { this.dismiss(); return; }
    this.bake(cx, (made) => {
      notify({ title: "Show", body: `Saved ${made.name}`, level: "success" });
      this.dismiss();
    });
  }

  send(cx) {
    const deliver = (item, cx) => {
      const pane = paste(absolute(item), cx);
      if (!pane) return;
      this.dismiss();
      run("pane.focus", { pane });
    };
    if (this.shapes.length === 0) deliver(this.mark, cx);
    else this.bake(cx, deliver);
  }

  renderMark() {
    const t = theme(), item = this.mark;
    const area = { width: (this.size?.width ?? 960) - 2 * PAD, height: (this.size?.height ?? 640) - TOOLBAR - 2 * PAD };
    const scale = previewable(item) ? Math.max(0.01, Math.min(area.width / item.width, area.height / item.height, 3)) : 0;
    const w = Math.round(item.width * scale), h = Math.round(item.height * scale);
    const stop = (_e, cx) => cx.stop_propagation();

    const button = (id, label, on, click, primary) => div().id(id).h(28).px(10).flex_none().flex().items_center().rounded(7).text_size(12)
      .border_1().border_color(primary ? t.solid : on ? t.accent : t.border)
      .bg(primary ? t.solid : on ? t.selected : t.raised).text_color(primary ? t.solid_foreground : on ? t.foreground : t.muted)
      .cursor_pointer().hover((s) => s.opacity(0.85)).on_mouse_down("left", stop).on_click(click).child(label);
    const tool = (name, label) => button(`tool-${name}`, label, this.tool === name, (_e, cx) => { this.tool = name; cx.notify(); });
    const swatch = (color) => div().id(`color-${color}`).size(18).flex_none().rounded(9).bg(color).cursor_pointer()
      .border(2).border_color(this.color === color ? t.foreground : t.popover)
      .on_mouse_down("left", stop).on_click((_e, cx) => { this.color = color; cx.notify(); });

    return v_flex().id("show-mark").size_full().min_h(0).bg(t.popover).text_color(t.foreground).text_size(13)
      .on_size_change((size, cx) => { this.size = size; cx.notify(); })
      .on_mouse_up("left", (_e, cx) => this.release(cx))
      .child(h_flex().h(TOOLBAR).flex_none().px(PAD).gap(6).items_center().border_b(1).border_color(t.border)
        .child(div().max_w(220).truncate().font_semibold().child(item.name))
        .child(div().w(8).flex_none())
        .child(tool("pen", "Pen"))
        .child(tool("arrow", "Arrow"))
        .child(tool("text", "Text"))
        .child(div().w(4).flex_none())
        .children(COLORS.map(swatch))
        .when(this.tool === "text", (el) => el.child(div().id("note").w(240).h(28).px(8).flex_none().flex().items_center().rounded(7)
          .border_1().border_color(t.input).bg(t.background).cursor_text().on_mouse_down("left", stop)
          .child(Input.new(this.note).h_full().text_size(12).text_color(t.foreground))))
        .child(div().flex_1())
        .child(button("undo", "Undo", false, (_e, cx) => { this.shapes.pop(); this.drawing = null; cx.notify(); }))
        .child(button("clear", "Clear", false, (_e, cx) => { this.shapes = []; this.drawing = null; cx.notify(); }))
        .child(div().w(4).flex_none())
        .child(button("open", "Open in viewer", false, () => { exec(opener(), [absolute(item)]).catch(fail); }))
        .child(button("save", this.busy ? "Saving…" : "Save copy", false, (_e, cx) => this.save(cx)))
        .child(button("send", "Send", false, (_e, cx) => this.send(cx), true))
        .child(button("close", "Esc", false, () => this.dismiss())))
      .child(div().flex_1().min_h(0).p(PAD).flex().items_center().justify_center()
        .child(scale > 0
          ? div().id("canvas").relative().w(w).h(h).flex_none().overflow_hidden().rounded(6)
            .on_mouse_down("left", (e, cx) => this.press(e, w, h, cx))
            .on_mouse_move((e, cx) => this.drag(e, w, h, cx))
            .on_mouse_up("left", (_e, cx) => this.release(cx))
            .child(image(`${ITEMS}/${item.file}`).w(w).h(h))
            .children(this.marks(w, h))
          : div().text_color(t.dim).child(`${item.name} has no preview`)));
  }
}
