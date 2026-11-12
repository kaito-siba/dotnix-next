// focus している pane で動いている Claude Code の scratchpad を preview する
// s を押した時と、pane から session を決められない時は、その folder で動いた全 session を新しい順で並べる
// 人に見せるファイルは scratchpad の out/ に置く約束 (Claude Code 側の指示で決めている)。既定では out/ だけを並べる
// scratchpad は <tmp>/claude-<uid>/<cwd の英数字以外を - にした名前>/<session id>/scratchpad にある
import { mkdir, readFile, readdir, unlink } from "fs/promises";
import { View, div, image } from "gpui-kit";
import { v_flex, h_flex, Editor, EditorState, TextView, Scrollbar, v_virtual_list, VirtualListScrollHandle, InputState, Input } from "gpui-base";
import { spaces, panes, focused, exec, hc, run, notify, appHome, readTextFile, watchFolder, theme, settings, props, closeOverlay } from "herdr";

const LANG = { ts: "js", tsx: "js", mts: "js", cts: "js", jsx: "js", mjs: "js", toml: "yaml", jsonc: "json", svelte: "html", vue: "html" };
const MAX_FILES = 500, MAX_PREVIEW = 400000, POLL = 5000, ROW = 28, PAD = 16;
const PICTURE = new Set(["png", "jpg", "jpeg", "gif", "webp", "svg"]);
// image() は app home からの相対 path しか読めないので、見せる画像はここへコピーする
const COPIES = "scratchpad/preview";
// app の asset loader の上限 (16 MiB)
const MAX_PICTURE = 16 * 1024 * 1024;

// Claude Code は起動した folder の名前で scratchpad を作るので、pane が下の階層に居ても見つかるよう親へ遡る
// 引数は folder、走査する範囲 (out か all)、all の時に返す件数、session id (空なら全 session)、all の時の filter の語 (glob を escape 済み)
// 範囲が out なら直下と out/ だけを見る。scratchpad には clone した repository 等で数万ファイルが入り得るので、全体は all の時だけ走査し、filter と件数の絞り込みもこちらで済ませる
// 出力は "mtime\tsize\tpath\0" の繰り返し
// find の -printf は GNU 専用で、macOS の find (BSD) には無い。その時は stat に同じ形で書かせる。macOS でも stat だけ GNU の事があるので、stat の種類も見る
const LIST = `
d=$1 mode=$2 max=$3 sid=$4
shift 4
tmp=\${CLAUDE_CODE_TMPDIR:-/tmp}
if find /dev/null -maxdepth 0 -printf '' 2>/dev/null; then
  files() { find "$@" -printf '%T@\\t%s\\t%p\\0' 2>/dev/null; }
elif stat -c %Y / >/dev/null 2>&1; then
  files() { find "$@" -print0 2>/dev/null | xargs -0 stat --printf='%.3Y\\t%s\\t%n\\0' 2>/dev/null; }
else
  files() { find "$@" -print0 2>/dev/null | xargs -0 stat -f '%m%t%z%t%N' 2>/dev/null | tr '\\n' '\\0'; }
fi
while :; do
  slug=$(printf %s "$d" | sed 's/[^A-Za-z0-9]/-/g')
  for s in "$tmp"/claude-*/"$slug"/*/scratchpad; do
    [ -d "$s" ] && break 2
  done
  [ "$d" = / ] && exit 0
  d=\${d%/*}
  [ -z "$d" ] && d=/
done
list() {
  for s in "$tmp"/claude-*/"$slug"/*/scratchpad; do
    [ -d "$s" ] || continue
    [ -z "$sid" ] || [ "$s" = "\${s%/*/scratchpad}/$sid/scratchpad" ] || continue
    if [ "$mode" = all ]; then
      root=$(printf %s "$s" | sed 's/[][*?\\\\]/\\\\&/g')
      (
        for term do set -- "$@" -ipath "$root/*$term*"; shift; done
        files "$s" \\( -name .git -o -name node_modules \\) -prune -o -type f "$@"
      )
    else
      files "$s" -maxdepth 1 -type f
      if [ -d "$s/out" ]; then
        files "$s/out" \\( -name .git -o -name node_modules \\) -prune -o -type f
      fi
    fi
  done
}
# sort と head の -z も GNU 専用なので、並べ替える間だけ改行区切りにする
if [ "$mode" = all ]; then list "$@" | tr '\\0' '\\n' | sort -rn | head -n "$max" | tr '\\n' '\\0'; else list; fi
`;

function location() {
  const space = spaces().find(s => s.active), f = focused();
  const pane = f?.pane ? panes().find(p => p.pane === f.pane) : null;
  return { cwd: pane?.cwd || f?.cwd || space?.folder, on: space?.machine ?? null, terminal: f?.terminal ?? pane?.terminal ?? null };
}

function parse(stdout, box) {
  const out = [];
  for (const record of stdout.split("\0")) {
    const [mtime, size, path] = record.split("\t");
    // 最初の scratchpad で切る。中に scratchpad という folder があっても、session を取り違えない
    const m = path?.match(/^(.*?\/([^/]+)\/scratchpad)\/(.+)$/);
    if (!m) continue;
    out.push({ box, path, root: m[1], session: m[2], rel: m[3], mtime: Number(mtime) * 1000, size: Number(size), key: `${box ?? ""}|${path}` });
  }
  return out;
}

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

// SVG は縦横比だけ分かれば良い。width と height は % の事があるので、viewBox を先に見る
function measureSvg(text) {
  const tag = text.match(/<svg\s[^>]*>/)?.[0];
  const attr = name => tag?.match(new RegExp(`\\s${name}\\s*=\\s*["']([^"']*)["']`))?.[1];
  const box = attr("viewBox")?.trim().split(/[\s,]+/).map(Number);
  if (box?.length === 4 && box[2] > 0 && box[3] > 0) return { width: box[2], height: box[3], vector: true };
  const [w, h] = [attr("width"), attr("height")].map(v => /^[\d.]+(px)?$/.test(v ?? "") ? parseFloat(v) : 0);
  return w > 0 && h > 0 ? { width: w, height: h, vector: true } : null;
}

function ago(ms) {
  const s = Math.max(0, (Date.now() - ms) / 1000);
  if (s < 60) return "now";
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}

function bytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

export default class Scratchpad extends View {
  init(_props, cx) {
    this.loc = location();
    this.files = []; this.rows = []; this.sel = null; this.shown = null;
    this.raw = false; this.error = null; this.loaded = false; this.picture = null; this.copies = 0;
    // local と inside (sbx の sandbox の中) を別々に走査する。found はその結果、busy は走査中の印
    this.found = { local: [], inside: [] }; this.busy = {}; this.gen = 0;
    // scope は focus している pane から決めた絞り込み先。undefined は調べている途中の印。wide は s で folder 全体に広げている印
    this.scope = undefined; this.wide = false;
    this.all = false; this.filter = ""; this.typing = false;
    this.input = InputState.new({ placeholder: "Filter by path…" });
    this.input.on("change", (_e, cx) => {
      // 検索を開いた / がそのまま入力される事があるので捨てる
      if (this.opening && this.input.value() === "/") { this.opening = false; this.input.set_value(""); return; }
      this.opening = false;
      this.filter = this.input.value(); this.rebuild(cx); cx.notify();
      // all の時の filter は走査の側で掛ける。1 文字ごとに走査しないよう、打ち終わりを待つ
      if (this.all) { this.typed?.cancel(); this.typed = cx.timer.after(200, cx => this.rescan(cx)); }
    });
    this.input.on("submit", (_e, cx) => { this.typing = false; this.handle.focus(); cx.notify(); });
    this.input.on("blur", (_e, cx) => { this.typing = false; cx.notify(); });
    this.scroll = VirtualListScrollHandle.new();
    this.handle = cx.focus_handle();
    this.handle.focus();
    // 開いた直後の focus は dialog の表示に奪われる事があるので、もう一度取る
    cx.timer.after(600, () => this.handle.focus());
    cx.timer.every(POLL, cx => this.refresh(cx));
    cx.spawn(async cx => {
      // 前に開いた時のコピーが残っている事がある (app が落ちた時など)
      const old = await readdir(`${appHome()}/${COPIES}`).catch(() => []);
      await Promise.all(old.map(name => this.drop({ path: `${appHome()}/${COPIES}/${name}` })));
      this.scope = await this.resolve(); cx.notify(); this.refresh(cx);
    });
  }

  async close() { await this.drop(this.picture); }

  // focus している pane で動いている Claude Code を調べて、表示をその session に絞る
  // 端末の foreground の pid から、Claude Code が ~/.claude/sessions/<pid>.json に書いている session id と起動した folder を引く
  // sbx 越しだと foreground は sbx で、中の session までは分からないので、sandbox の中だけに絞る
  // Claude Code が動いていない pane は null。その時は folder で動いた全 session を並べる
  async resolve() {
    const { terminal, on } = this.loc;
    if (!terminal) return null;
    try {
      const fg = JSON.parse((await hc(["get", terminal, "--json"])).stdout).foreground;
      if (!fg) return null;
      if (fg.name === "sbx") return on ? null : { box: true };
      const r = await exec("sh", ["-c", 'cat "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions/$1.json"', "session", String(fg.pid)], { on });
      const { sessionId, cwd } = JSON.parse(r.stdout);
      return sessionId && cwd ? { id: sessionId, cwd } : null;
    } catch { return null; }
  }

  // 今の絞り込み先。s で folder 全体に広げている時と、pane から決められなかった時は null
  only() { return this.wide ? null : this.scope; }

  terms() { return this.filter.toLowerCase().split(/\s+/).filter(Boolean); }

  // sbx exec は止まっている sandbox を起動してしまうので、動いている物だけを毎回調べ直す
  // この folder を workspace に含まない sandbox に、ここの scratchpad は無い
  async sandboxes() {
    const { cwd, on } = this.loc;
    if (on) return [];
    try {
      const r = await exec("sbx", ["ls", "--json"]);
      if (r.code !== 0) return [];
      return JSON.parse(r.stdout).filter(box => box.status === "running" && box.workspaces.some(w => {
        // "host の path:中の path" の形と、両方が同じ path の時の path だけの形がある
        const dir = w.split(":")[1] ?? w;
        return cwd === dir || cwd.startsWith(dir + "/");
      })).map(box => box.name);
    } catch { return []; }
  }

  async local(args) {
    if (this.only()?.box) return [];
    return parse((await exec("sh", args, { on: this.loc.on })).stdout, null);
  }

  // sbx の sandbox は microVM なので、中の /tmp は sbx exec 越しにしか読めない
  async inside(args) {
    if (this.only()?.id) return [];
    const lists = await Promise.all((await this.sandboxes()).map(box =>
      exec("sbx", ["exec", box, "sh", ...args]).then(r => r.code === 0 ? parse(r.stdout, box) : [], () => [])));
    return lists.flat();
  }

  // sbx 越しの走査は遅いので、local の表示を待たせないよう part ("local" か "inside") ごとに走る
  scan(cx, part) {
    if (this.busy[part]) return;
    this.busy[part] = true;
    const only = this.only(), gen = this.gen, local = part === "local";
    const terms = this.all ? this.terms().map(term => term.replace(/[\\*?[\]]/g, "\\$&")) : [];
    const args = ["-c", LIST, "scratchpad", only?.cwd ?? this.loc.cwd, this.all ? "all" : "out", String(MAX_FILES), only?.id ?? "", ...terms];
    cx.spawn(async cx => {
      try {
        this.found[part] = await (local ? this.local(args) : this.inside(args));
        this.files = [...this.found.local, ...this.found.inside].sort((a, b) => b.mtime - a.mtime); this.rebuild(cx);
        if (local) { this.error = null; this.watch(cx); }
      } catch (e) { if (local) this.error = String(e); }
      finally {
        this.busy[part] = false;
        if (!this.busy.local && !this.busy.inside) this.loaded = true;
        cx.notify();
        if (gen !== this.gen) this.scan(cx, part);
      }
    });
  }

  refresh(cx) {
    if (!this.loc.cwd || this.scope === undefined) return;
    this.scan(cx, "local"); this.scan(cx, "inside");
  }

  // 走査の条件 (a, s, all の時の filter) が変わった時に呼ぶ。走査の途中なら、終わってから今の条件で取り直す
  rescan(cx) { this.gen++; this.refresh(cx); }

  // sbx exec 越しの sandbox は watch できないので、そちらは POLL 頼み
  // directory が多すぎる tree は watch を断られる。張り直しても同じなので、その後は POLL に任せる
  watch(cx) {
    const local = this.found.local[0];
    if (!local || this.loc.on || this.watched) return;
    const dir = local.root.replace(/\/[^/]+\/scratchpad$/, "");
    this.watched = dir;
    cx.spawn(async cx => {
      try { for (;;) { await watchFolder(dir); this.scan(cx, "local"); } }
      catch {}
    });
  }

  rebuild(cx) {
    const sessions = new Map();
    for (const f of this.files) {
      const id = `${f.box ?? ""}|${f.session}`;
      if (!sessions.has(id)) sessions.set(id, { id, box: f.box, session: f.session, all: [] });
      sessions.get(id).all.push(f);
    }
    const terms = this.terms();
    let left = MAX_FILES;
    this.rows = [];
    for (const s of sessions.values()) {
      let files = s.all;
      if (!this.all) {
        // out/ をまだ使っていない session は、直下のファイルで代える
        const out = files.filter(f => f.rel.startsWith("out/"));
        files = out.length ? out : files.filter(f => !f.rel.includes("/"));
      }
      for (const f of files) f.label = !this.all && f.rel.startsWith("out/") ? f.rel.slice(4) : f.rel;
      if (terms.length) files = files.filter(f => { const rel = f.rel.toLowerCase(); return terms.every(term => rel.includes(term)); });
      s.files = files.slice(0, left);
      left -= s.files.length;
      if (s.files.length) this.rows.push({ head: s }, ...s.files.map(file => ({ file })));
    }
    const current = this.rows.find(r => r.file?.key === this.sel)?.file;
    if (!current) this.select(this.rows.find(r => r.file)?.file ?? null, cx);
    else if (current.mtime !== this.shown?.mtime) this.show(current, cx);
  }

  select(file, cx) {
    this.sel = file?.key ?? null;
    const at = this.rows.findIndex(r => r.file?.key === this.sel);
    if (at >= 0) this.scroll.scroll_to_item(at, "center");
    this.show(file, cx);
  }

  move(step, cx) {
    const list = this.rows.filter(r => r.file).map(r => r.file);
    if (!list.length) return;
    const at = list.findIndex(f => f.key === this.sel);
    this.select(list[Math.min(list.length - 1, Math.max(0, at + step))], cx);
    cx.notify();
  }

  show(file, cx) {
    this.shown = file;
    if (!file) { this.code?.release(); this.code = null; this.text = null; this.note = null; this.drop(this.picture); this.picture = null; return; }
    cx.spawn(async cx => {
      const ext = file.rel.includes(".") ? file.rel.split(".").pop().toLowerCase() : "txt";
      // sandbox と他の machine のファイルは app home へコピーできないので、画像としては出さない
      const drawn = PICTURE.has(ext) && !file.box && !this.loc.on;
      let text = null, note = null, picture = null;
      try {
        if (file.box) {
          const r = await exec("sbx", ["exec", file.box, "head", "-c", String(MAX_PREVIEW + 1), file.path], { timeout: 10000 });
          if (r.code === 0) text = r.stdout; else note = r.stderr.trim() || "Cannot read this file";
        } else if (!drawn || ext === "svg") {
          text = await readTextFile(file.path, { on: this.loc.on });
          if (text === null) note = "This file is no longer available";
        }
        // SVG は文字としても読めるので、描けない時は文字のまま見せる
        if (drawn && (text !== null || ext !== "svg")) {
          picture = await this.copy(file, ext, text);
          if (!picture && text === null) note = file.size > MAX_PICTURE ? "Image is too large to preview" : "Cannot preview this image";
        }
      } catch { note = "Cannot preview this file (binary, too large, or unreadable)"; }
      if (this.shown !== file) { this.drop(picture); return; }
      if (text?.includes("\0")) { text = null; note = "Binary file · no text preview"; }
      if (text && text.length > MAX_PREVIEW) text = text.slice(0, MAX_PREVIEW) + "\n… (file truncated)";
      this.code?.release(); this.code = null; this.text = text; this.note = note;
      this.drop(this.picture); this.picture = picture;
      this.markdown = text !== null && (ext === "md" || ext === "markdown");
      if (text !== null) {
        const t = theme();
        this.code = EditorState.new({ language: LANG[ext] ?? ext, readonly: true, value: text, soft_wrap: this.markdown,
          font_family: settings().font_family, font_size: 12,
          syntax: { keyword: t.ansi5, string: t.ansi2, comment: t.dim, function: t.ansi4, type: t.ansi3, number: t.ansi1, constant: t.ansi6 } });
      }
      cx.notify();
    });
  }

  // 同じ path の画像は描画が cache されて、中身が変わっても古いままになる。コピーは毎回違う名前にする
  async copy(file, ext, text) {
    if (file.size > MAX_PICTURE) return null;
    const name = `${COPIES}/${Date.now()}-${++this.copies}.${ext}`, path = `${appHome()}/${name}`;
    await mkdir(`${appHome()}/${COPIES}`, { recursive: true });
    if ((await exec("cp", ["--", file.path, path])).code !== 0) return null;
    const size = text === null ? measure(await readFile(path)) : measureSvg(text);
    if (!size?.width || !size.height) { this.drop({ path }); return null; }
    return { name, path, ...size };
  }

  drop(picture) { return picture ? unlink(picture.path).catch(() => {}) : null; }

  key(e, cx) {
    if (e.modifiers.control || e.modifiers.alt || e.modifiers.platform) return;
    if (this.typing) {
      if (e.key === "escape") this.search(false, cx);
      else if (e.key === "down") this.move(1, cx);
      else if (e.key === "up") this.move(-1, cx);
      else return;
      return cx.stop_propagation();
    }
    if (e.key === "escape") { if (this.filter) this.search(false, cx); else closeOverlay(props().overlay); }
    else if (e.key === "q") closeOverlay(props().overlay);
    else if (e.key === "/") this.search(true, cx);
    else if (e.key === "a") { this.all = !this.all; this.rescan(cx); cx.notify(); }
    else if (e.key === "s" && this.scope) { this.wide = !this.wide; this.rescan(cx); cx.notify(); }
    else if (e.key === "j" || e.key === "down") this.move(1, cx);
    else if (e.key === "k" || e.key === "up") this.move(-1, cx);
    else if (e.key === "g") this.move(e.modifiers.shift ? Infinity : -Infinity, cx);
    else if (e.key === "m") { this.raw = !this.raw; cx.notify(); }
    else if (e.key === "r") this.refresh(cx);
    else if (e.key === "y" && this.shown) { cx.write_to_clipboard(this.shown.path); this.copied = this.shown.key; cx.notify(); }
    else if (e.key === "p" && this.shown) this.paste(cx);
    else return;
    cx.stop_propagation();
  }

  // path を focus している端末の prompt に貼って閉じる。改行は送らないので、続けて指示を書ける
  // 貼るのは clipboard 越し (terminal.paste) なので、clipboard は path で上書きされる
  paste(cx) {
    const f = focused(), pane = f?.pane ? panes().find(p => p.pane === f.pane) : null;
    if (!pane?.terminal) { notify({ title: "Scratchpad", body: "Focus a terminal pane first, then paste again", level: "warning" }); return; }
    cx.write_to_clipboard(`${this.shown.path} `);
    run("terminal.paste");
    closeOverlay(props().overlay);
    run("pane.focus", { pane: pane.pane });
  }

  search(open, cx) {
    this.typing = open;
    if (open) { this.opening = true; this.input.focus(); }
    else { this.filter = ""; this.input.set_value(""); this.handle.focus(); this.rebuild(cx); if (this.all) this.rescan(cx); }
    cx.notify();
  }

  empty() {
    if (this.error) return this.error;
    if (!this.loc.cwd) return "No folder";
    if (!this.loaded) return "Loading…";
    if (this.filter) return "No files match the filter";
    const keys = [!this.all && "a for all files", this.only() && "s for all sessions"].filter(Boolean);
    return `${this.all ? "No scratchpad files" : "Nothing in out/"}${keys.length ? ` · press ${keys.join(", ")}` : ""}`;
  }

  // virtual list の renderer の中では on_click 等の handler を登録できない。click は list 側の on_item_click で受ける
  row(row, t) {
    if (row.head) {
      const s = row.head;
      return h_flex().h(ROW).px(8).gap(6).items_center().text_size(11).text_color(t.dim)
        .child(div().font_semibold().text_color(t.muted).child(s.session.slice(0, 8)))
        .when(Boolean(s.box), el => el.child(div().px(5).rounded(4).border_1().border_color(t.border).text_size(10).child(`sbx:${s.box}`)))
        .child(div().flex_1())
        .child(div().child(`${s.files.length} files · ${ago(s.files[0].mtime)}`));
    }
    const f = row.file, parts = f.label.split("/"), name = parts.pop();
    return h_flex().h(ROW).px(8).gap(8).items_center().rounded(7).cursor_pointer()
      .when(this.sel === f.key, el => el.bg(t.selected)).hover(s => s.bg(t.hover))
      .child(h_flex().flex_1().min_w(0)
        .child(div().text_color(t.dim).truncate().child(parts.length ? parts.join("/") + "/" : ""))
        .child(div().min_w(0).truncate().child(name)))
      .child(div().flex_none().text_size(11).text_color(t.dim).child(ago(f.mtime)));
  }

  list(t) {
    const rows = this.rows;
    return v_flex().w(320).h_full().flex_none().border_r(1).border_color(t.border)
      .when(this.typing || Boolean(this.filter), el => el.child(div().flex_none().p(6).child(
        Input.new(this.input).h(30).px(8).rounded(7).border_1().border_color(this.typing ? t.accent : t.border).bg(t.background).text_size(12).text_color(t.foreground))))
      .child(div().flex_1().min_h(0).relative()
      .child(v_virtual_list("sp-list", rows.length, ROW, i => rows[i].file?.key ?? `head:${rows[i].head.id}`,
        range => rows.slice(range.start, range.end).map(row => this.row(row, t)))
        .track_scroll(this.scroll).size_full().px(6)
        .on_item_click((key, cx) => {
          const file = this.files.find(f => f.key === key);
          if (!file) return;
          this.select(file, cx); this.handle.focus(); cx.notify();
        }))
      .child(Scrollbar.vertical("sp-list").absolute().inset_0()));
  }

  // 領域に収まる大きさで置く。写真は元の大きさより拡げない
  // 透過した画像は白地を前提にした物が多いので、下に白を敷く
  drawing(p) {
    const area = this.area ?? { width: 800, height: 600 };
    const fit = Math.min((area.width - 2 * PAD) / p.width, (area.height - 2 * PAD) / p.height);
    const scale = Math.max(0.01, p.vector ? fit : Math.min(fit, 1));
    const w = Math.round(p.width * scale), h = Math.round(p.height * scale);
    return div().id("sp-picture").flex_1().min_h(0).w_full().flex().items_center().justify_center().overflow_hidden()
      .on_size_change((size, cx) => { this.area = size; cx.notify(); })
      .child(div().w(w).h(h).flex_none().bg("#ffffff").child(image(p.name).w(w).h(h)));
  }

  preview(t) {
    const f = this.shown;
    if (!f) return div().p(16).text_color(t.dim).child(this.empty());
    const body = this.picture && !(this.raw && this.code) ? this.drawing(this.picture)
      : this.code === null ? div().p(16).text_color(t.dim).child(this.note || "Loading file…")
      : this.markdown && !this.raw ? v_flex().id("sp-markdown").flex_1().min_h(0).overflow_y_scrollbar().px(20).py(14).text_size(13).child(TextView.markdown(`sp-md-${f.key}`, this.text).selectable(true))
      : Editor.new(this.code).flex_1().min_h(0);
    return v_flex().flex_1().min_w(0).min_h(0)
      .child(h_flex().h(34).flex_none().px(14).gap(10).items_center().border_b(1).border_color(t.border).text_size(11).text_color(t.dim)
        .child(div().id("sp-path").flex_1().min_w(0).truncate().cursor_pointer().hover(s => s.text_color(t.foreground))
          .on_click((_e, cx) => { cx.write_to_clipboard(f.path); this.copied = f.key; cx.notify(); })
          .child(this.copied === f.key ? "Copied path" : f.path))
        .child(div().flex_none().child(`${bytes(f.size)} · ${new Date(f.mtime).toLocaleString()}`)))
      .child(body);
  }

  render() {
    const t = theme();
    const only = this.only(), mine = this.scope?.id ? "this session" : "this sandbox";
    const hint = `j/k move · / filter · a ${this.all ? "out/ only" : "all files"} · ${this.scope ? `s ${this.wide ? mine : "all sessions"} · ` : ""}${this.markdown || (this.picture && this.code) ? "m raw/rendered · " : ""}y copy path · p paste to prompt · r rescan · q close`;
    // dialog の枠は角丸だが、中身は角丸に切り抜かれない。背景も同じ丸みにして、角からはみ出させない
    return v_flex().id("scratchpad").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .size_full().min_h(0).rounded(10).bg(t.popover).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(10).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().child("Scratchpad"))
        .child(div().text_size(12).text_color(t.dim).child(`${(only?.cwd ?? this.loc.cwd)?.split("/").pop() ?? ""}${this.scope ? ` · ${only ? mine : "all sessions"}` : ""}`))
        .child(div().flex_1())
        .child(div().text_size(11).text_color(t.dim).child(hint)))
      .child(h_flex().flex_1().min_h(0).items_start()
        .child(this.list(t))
        .child(this.preview(t).h_full()));
  }
}
