// sbx (Docker Sandboxes) の sandbox を見る dialog。Files / Ports / Network / Metrics の 4 面がある
// Files は sandbox の中を yazi のように hjkl で辿り、preview して、host へコピーする
// Ports は host への port の公開、Network は遮断された通信を探して sandbox 単位で許可する
// sandbox は microVM なので、中の事は全て sbx exec 越しに調べる。sbx exec は止まっている sandbox を起動してしまうので、動いている物にしか使わない
import { mkdir, readFile, readdir, unlink } from "fs/promises";
import { View, div, image } from "gpui-kit";
import { v_flex, h_flex, Editor, EditorState, TextView, Scrollbar, v_virtual_list, VirtualListScrollHandle, InputState, Input } from "gpui-base";
import { spaces, panes, focused, exec, notify, appHome, theme, settings, props, closeOverlay, nextCommand } from "herdr";

const TABS = ["files", "ports", "network", "metrics"];
const TITLE = { files: "Files", ports: "Ports", network: "Network", metrics: "Metrics" };
const LANG = { ts: "js", tsx: "js", mts: "js", cts: "js", jsx: "js", mjs: "js", toml: "yaml", jsonc: "json", svelte: "html", vue: "html" };
const ROW = 28, PAD = 16, POLL = 5000, MAX_PREVIEW = 400000, MAX_ENTRIES = 5000, HISTORY = 60;
const PICTURE = new Set(["png", "jpg", "jpeg", "gif", "webp"]);
// image() は app home からの相対 path しか読めないので、見せる画像はここへコピーする
const COPIES = "sandbox/preview";
// app の asset loader の上限 (16 MiB)
const MAX_PICTURE = 16 * 1024 * 1024;

// 出力は "種類\tsize\tmtime\t名前\0" の繰り返し。種類は link を辿った先の物 (d が directory)
const LIST = `cd "$1" 2>/dev/null || exit 3; find . -mindepth 1 -maxdepth 1 -printf '%Y\\t%s\\t%T@\\t%f\\0' 2>/dev/null`;
// CPU の使用率は /proc/stat の差から出すので、間を空けて 2 回読む
const METRICS = `head -1 /proc/stat; sleep 0.5; head -1 /proc/stat; nproc; cat /proc/loadavg
grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; df -kP / | tail -1
echo ---; ps -eo pcpu,rss,pid,args --sort=-pcpu 2>/dev/null | head -9`;
// host へコピーして、置いた folder を返す。host が他の machine の事もあるので、home はその machine に聞く
const SAVE = `d="$HOME/Downloads/sbx/$1"; mkdir -p "$d" && sbx cp "$1:$2" "$d/" >&2 && printf %s "$d"`;

function location() {
  const space = spaces().find(s => s.active), f = focused();
  const pane = f?.pane ? panes().find(p => p.pane === f.pane) : null;
  return { cwd: pane?.cwd || f?.cwd || space?.folder, on: space?.machine ?? null };
}

// "host の path:中の path" の形と、両方が同じ path の時の path だけの形がある
const inside = w => w.split(":")[1] ?? w;
const within = (dir, path) => path === dir || path?.startsWith(dir.replace(/\/$/, "") + "/");
const join = (dir, name) => `${dir.replace(/\/$/, "")}/${name}`;
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

function ago(ms) {
  const s = Math.max(0, (Date.now() - ms) / 1000);
  if (s < 60) return "now";
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}

function bytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 ** 2) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 ** 3) return `${(n / 1024 ** 2).toFixed(1)} MB`;
  return `${(n / 1024 ** 3).toFixed(1)} GB`;
}

export default class Sandbox extends View {
  init(_props, cx) {
    this.loc = location();
    // boxes の null は取っている途中の印
    this.boxes = null; this.name = null; this.tab = "files";
    this.busy = {}; this.error = {}; this.copies = 0;
    this.sel = { ports: null, network: null };
    this.filter = { files: "", network: "" };
    // typing は入力欄の使い道: filter (絞り込み) か port (公開する port)。null は入力していない
    this.typing = null;
    this.input = InputState.new({ placeholder: "" });
    this.input.on("change", (_e, cx) => {
      // 入力欄を開いた key がそのまま入力される事があるので捨てる
      if (this.opening && this.input.value() === this.opening) { this.opening = null; this.input.set_value(""); return; }
      this.opening = null;
      if (this.typing === "filter") { this.filter[this.tab] = this.input.value(); this.sync(cx); cx.notify(); }
    });
    this.input.on("submit", (_e, cx) => {
      if (this.typing === "port") this.publish(this.input.value().trim(), cx);
      this.type(null, cx, true);
    });
    this.input.on("blur", (_e, cx) => { this.typing = null; cx.notify(); });
    this.scroll = Object.fromEntries(TABS.map(tab => [tab, VirtualListScrollHandle.new()]));
    this.reset();
    this.handle = cx.focus_handle();
    this.handle.focus();
    // 開いた直後の focus は dialog の表示に奪われる事があるので、もう一度取る
    cx.timer.after(600, () => this.handle.focus());
    cx.timer.every(POLL, cx => this.refresh(cx));
    // keys.json から面を直に開ける: "sandbox.network" 等
    cx.spawn(async cx => { for (;;) { const c = await nextCommand(); if (TABS.includes(c)) this.show(c, cx); } });
    cx.spawn(async cx => {
      // 前に開いた時のコピーが残っている事がある (app が落ちた時など)
      const old = await readdir(`${appHome()}/${COPIES}`).catch(() => []);
      await Promise.all(old.map(name => this.drop({ path: `${appHome()}/${COPIES}/${name}` })));
      this.refresh(cx);
    });
  }

  async close() { await this.drop(this.picture); }

  // sandbox ごとの状態。sandbox を切り替えたら捨てる
  reset() {
    this.dirs = new Map(); this.at = new Map(); this.dir = null;
    this.shown = null; this.code?.release(); this.code = null; this.text = null; this.why = null;
    this.drop(this.picture); this.picture = null;
    this.ports = null; this.listening = []; this.net = null; this.metrics = null; this.history = [];
  }

  box() { return this.boxes?.find(b => b.name === this.name) ?? null; }
  running() { return this.box()?.status === "running"; }

  async sbx(args, options) {
    const r = await exec("sbx", args, { on: this.loc.on, ...options });
    if (r.code !== 0) throw new Error(r.stderr.trim().split("\n").pop() || `sbx ${args[0]} failed`);
    return r.stdout;
  }

  // 同じ物を重ねて取りに行かない。失敗は面ごとに覚えて、その面に出す
  load(cx, part, fn) {
    if (this.busy[part]) return;
    this.busy[part] = true;
    const name = this.name;
    cx.spawn(async cx => {
      try { await fn(cx, name); this.error[part] = null; }
      catch (e) { if (name === this.name) this.error[part] = String(e?.message ?? e); }
      finally { this.busy[part] = false; cx.notify(); }
    });
  }

  refresh(cx) {
    this.load(cx, "boxes", async cx => {
      this.boxes = JSON.parse(await this.sbx(["ls", "--json"]));
      if (!this.box()) this.pick(this.start(), cx);
    });
    if (!this.box()) return;
    const tab = this.tab;
    if (tab === "files" && this.running()) this.list(cx, this.dir, true);
    else if (tab === "ports") this.loadPorts(cx);
    else if (tab === "network") this.loadNet(cx);
    else if (tab === "metrics" && this.running()) { this.loadMetrics(cx); this.loadNet(cx); }
  }

  // 最初に見せる sandbox: focus している pane の folder を workspace に持つ物、無ければ動いている物
  start() {
    const { cwd } = this.loc, boxes = this.boxes ?? [];
    const mine = boxes.filter(b => cwd && b.workspaces?.some(w => within(w.split(":")[0], cwd)));
    return (mine.find(b => b.status === "running") ?? mine[0] ?? boxes.find(b => b.status === "running") ?? boxes[0])?.name ?? null;
  }

  pick(name, cx) {
    if (name === this.name) return;
    this.name = name; this.error = {}; this.reset();
    const box = this.box();
    if (!box) return;
    // pane が workspace の中に居れば、そこから始める
    const roots = (box.workspaces ?? []).map(inside), { cwd } = this.loc;
    const host = (box.workspaces ?? []).find(w => cwd && within(w.split(":")[0], cwd));
    this.dir = host ? inside(host) + cwd.slice(host.split(":")[0].length) : roots[0] ?? "/";
    this.refresh(cx);
  }

  cycle(step, cx) {
    const boxes = this.boxes ?? [];
    if (boxes.length < 2) return;
    const at = boxes.findIndex(b => b.name === this.name);
    this.pick(boxes[(at + step + boxes.length) % boxes.length].name, cx);
  }

  show(tab, cx) {
    this.tab = tab; this.type(null, cx);
    this.refresh(cx);
  }

  // ---- Files

  list(cx, dir, again) {
    if (!dir || (!again && this.dirs.has(dir))) return;
    this.load(cx, `dir:${dir}`, async (cx, name) => {
      const r = await exec("sbx", ["exec", name, "sh", "-c", LIST, "ls", dir], { on: this.loc.on });
      if (name !== this.name) return;
      if (r.code !== 0) { this.dirs.set(dir, { error: r.code === 3 ? "Cannot open this folder" : r.stderr.trim().split("\n").pop() || "Cannot list this folder" }); return; }
      const entries = [];
      for (const record of r.stdout.split("\0")) {
        const [kind, size, mtime, ...rest] = record.split("\t");
        if (!rest.length) continue;
        const file = rest.join("\t");
        entries.push({ name: file, path: join(dir, file), dir: kind === "d", size: Number(size), mtime: Number(mtime) * 1000 });
      }
      entries.sort((a, b) => b.dir - a.dir || a.name.localeCompare(b.name));
      this.dirs.set(dir, { entries: entries.slice(0, MAX_ENTRIES), more: entries.length > MAX_ENTRIES });
      this.sync(cx);
    });
  }

  entries(dir = this.dir) {
    const terms = dir === this.dir ? this.filter.files.toLowerCase().split(/\s+/).filter(Boolean) : [];
    return (this.dirs.get(dir)?.entries ?? []).filter(e => (this.hidden || !e.name.startsWith(".")) && terms.every(term => e.name.toLowerCase().includes(term)));
  }

  current() {
    const list = this.entries();
    return list.find(e => e.name === this.at.get(this.dir)) ?? list[0] ?? null;
  }

  // 選んでいる物が変わっていたら preview を取り直す。directory なら中身を先に読んでおく
  sync(cx) {
    if (this.tab !== "files") return;
    const e = this.current();
    if (e?.dir) this.list(cx, e.path);
    if ((e?.path ?? null) !== this.shown?.path || e?.mtime !== this.shown?.mtime) this.preview(e, cx);
  }

  enter(cx) {
    const e = this.current();
    if (!e?.dir) return;
    this.dir = e.path; this.filter.files = "";
    this.list(cx, this.dir, true); this.sync(cx);
  }

  leave(cx) {
    if (!this.dir || this.dir === "/") return;
    const from = this.dir;
    this.dir = parent(from); this.filter.files = "";
    // 戻った先では、出てきた folder を選んでおく
    this.at.set(this.dir, from.split("/").filter(Boolean).pop());
    this.list(cx, this.dir); this.sync(cx);
  }

  preview(entry, cx) {
    this.shown = entry;
    if (!entry || entry.dir) { this.code?.release(); this.code = null; this.text = null; this.why = null; this.drop(this.picture); this.picture = null; return; }
    const name = this.name;
    cx.spawn(async cx => {
      const ext = entry.name.includes(".") ? entry.name.split(".").pop().toLowerCase() : "txt";
      // 他の machine の sandbox からは app home へコピーできないので、画像としては出さない
      const drawn = PICTURE.has(ext) && !this.loc.on;
      let text = null, note = null, picture = null;
      try {
        if (drawn) {
          picture = await this.copy(name, entry, ext);
          if (!picture) note = entry.size > MAX_PICTURE ? "Image is too large to preview" : "Cannot preview this image";
        } else {
          const r = await exec("sbx", ["exec", name, "head", "-c", String(MAX_PREVIEW + 1), entry.path], { on: this.loc.on });
          if (r.code === 0) text = r.stdout; else note = r.stderr.trim().split("\n").pop() || "Cannot read this file";
        }
      } catch { note = "Cannot preview this file (binary, too large, or unreadable)"; }
      if (this.shown !== entry) { this.drop(picture); return; }
      if (text?.includes("\0")) { text = null; note = "Binary file · no text preview"; }
      if (text && text.length > MAX_PREVIEW) text = text.slice(0, MAX_PREVIEW) + "\n… (file truncated)";
      this.code?.release(); this.code = null; this.text = text; this.why = note;
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
  async copy(box, entry, ext) {
    if (entry.size > MAX_PICTURE) return null;
    const name = `${COPIES}/${Date.now()}-${++this.copies}.${ext}`, path = `${appHome()}/${name}`;
    await mkdir(`${appHome()}/${COPIES}`, { recursive: true });
    if ((await exec("sbx", ["cp", `${box}:${entry.path}`, path])).code !== 0) return null;
    const size = measure(await readFile(path));
    if (!size?.width || !size.height) { this.drop({ path }); return null; }
    return { name, path, ...size };
  }

  drop(picture) { return picture ? unlink(picture.path).catch(() => {}) : null; }

  // 選んでいる file か folder を、host の ~/Downloads/sbx/<sandbox>/ へコピーする。置いた path は clipboard に入れる
  save(cx) {
    const e = this.current();
    if (!e) return;
    this.load(cx, "save", async (cx, name) => {
      const r = await exec("sh", ["-c", SAVE, "save", name, e.path], { on: this.loc.on });
      if (r.code !== 0) { notify({ title: "Sandbox", body: r.stderr.trim().split("\n").pop() || "Copy failed", level: "error" }); return; }
      const path = join(r.stdout, e.name);
      cx.write_to_clipboard(path);
      notify({ title: "Copied to host", body: `${path}${this.loc.on ? ` on ${this.loc.on}` : ""} · path is on the clipboard`, level: "success" });
    });
  }

  // ---- Ports

  loadPorts(cx) {
    this.load(cx, "ports", async (cx, name) => {
      const ports = JSON.parse(await this.sbx(["ports", name, "--json"])) ?? [];
      // 中で待ち受けている port も並べて、そのまま公開できるようにする。ss が無い image では出ない
      let listening = [];
      if (this.running()) {
        const r = await exec("sbx", ["exec", name, "sh", "-c", "ss -Hltn 2>/dev/null"], { on: this.loc.on }).catch(() => null);
        listening = [...new Set((r?.stdout ?? "").split("\n").map(line => Number(line.trim().split(/\s+/)[3]?.split(":").pop())).filter(Boolean))].sort((a, b) => a - b);
      }
      if (name !== this.name) return;
      this.ports = ports; this.listening = listening;
    });
  }

  portRows() {
    const ports = this.ports ?? [], open = this.listening.filter(port => !ports.some(p => p.sandbox_port === port));
    return [
      { key: "head:published", head: `Published · ${ports.length}` },
      ...ports.map(p => ({ key: `p:${p.host_ip}:${p.host_port}:${p.sandbox_port}/${p.protocol}`, port: p })),
      ...(open.length ? [{ key: "head:listening", head: `Listening in the sandbox · ${open.length}` }, ...open.map(port => ({ key: `l:${port}`, listen: port }))] : []),
    ];
  }

  // spec は sbx ports の --publish の形: [[HOST_IP:]HOST_PORT:]SANDBOX_PORT[/PROTOCOL]
  publish(spec, cx) {
    if (!spec) return;
    this.load(cx, "publish", async (cx, name) => {
      try { notify({ title: "Sandbox", body: (await this.sbx(["ports", name, "--publish", spec])).trim().split("\n").pop(), level: "success" }); }
      catch (e) { notify({ title: "Sandbox", body: String(e.message), level: "error" }); }
      this.loadPorts(cx);
    });
  }

  unpublish(p, cx) {
    this.load(cx, "publish", async (cx, name) => {
      try { await this.sbx(["ports", name, "--unpublish", `${p.host_ip}:${p.host_port}:${p.sandbox_port}/${p.protocol}`]); }
      catch (e) { notify({ title: "Sandbox", body: String(e.message), level: "error" }); }
      this.loadPorts(cx);
    });
  }

  // ---- Network

  loadNet(cx) {
    this.load(cx, "network", async (cx, name) => {
      const [approvals, log, rules] = await Promise.all([
        this.sbx(["policy", "approval", "ls", "--json"]), this.sbx(["policy", "log", name, "--json"]), this.sbx(["policy", "ls", name, "--json", "--type", "network"]),
      ]);
      if (name !== this.name) return;
      this.net = {
        pending: (JSON.parse(approvals) ?? []).filter(a => a.sandbox_name === name),
        log: JSON.parse(log) ?? {}, rules: JSON.parse(rules)?.rules ?? [],
      };
    });
  }

  // 遮断された通信を host ごとにまとめる。state は pending (許可待ち)、allowed (その後に許可された)、blocked
  // 許可されたかは、host そのままの allow rule があるか、遮断より後に通った記録があるかで見る。wildcard の rule までは読まない
  netRows() {
    const net = this.net;
    if (!net) return [];
    const terms = this.filter.network.toLowerCase().split(/\s+/).filter(Boolean);
    const match = text => terms.every(term => text.toLowerCase().includes(term));
    const time = s => s ? Date.parse(s) : 0;
    const rules = net.rules.filter(r => r.resource_type === "network");
    const granted = new Set(rules.filter(r => r.decision === "allow" && r.status === "active").flatMap(r => r.resources));
    const passed = new Map((net.log.allowed ?? []).map(a => [a.host, time(a.last_seen)]));
    const hosts = new Map();
    for (const b of net.log.blocked ?? []) hosts.set(b.host, { host: b.host, count: b.count, last: time(b.last_seen), reason: b.reason });
    for (const a of net.pending) hosts.set(a.title, { ...(hosts.get(a.title) ?? { host: a.title, count: 0, last: time(a.created_at) }), approval: a });
    const order = { pending: 0, blocked: 1, allowed: 2 };
    const blocked = [...hosts.values()].filter(h => match(h.host)).map(h => ({
      ...h, key: `b:${h.host}`,
      state: granted.has(h.host) || granted.has(h.host.replace(/:\d+$/, "")) || (passed.get(h.host) ?? 0) > h.last ? "allowed" : h.approval ? "pending" : "blocked",
    })).sort((a, b) => order[a.state] - order[b.state] || b.last - a.last);
    const allowed = (net.log.allowed ?? []).filter(a => match(a.host)).map(a => ({ key: `a:${a.host}`, pass: a, last: time(a.last_seen) })).sort((a, b) => b.last - a.last);
    const listed = rules.filter(r => match(r.resources.join(" "))).map(r => ({ key: `r:${r.id}`, rule: r, own: r.editable && r.scope === `sandbox:${this.name}` }));
    const section = (title, items) => items.length ? [{ key: `head:${title}`, head: `${title} · ${items.length}` }, ...items] : [];
    return [...section("Blocked", blocked), ...section("Allowed", allowed), ...section("Rules", listed)];
  }

  // この sandbox だけに許可する。許可待ちの物は approval に答え (中で待っている通信がそのまま通る)、他は sandbox に絞った allow rule を足す
  allow(rows, cx) {
    const todo = rows.filter(r => r.host && r.state !== "allowed");
    if (!todo.length) return;
    this.load(cx, "allow", async (cx, name) => {
      const failed = [];
      for (const r of todo) {
        try {
          if (r.approval) await this.sbx(["policy", "approval", "respond", r.approval.id, "--option", "allow"]);
          else await this.sbx(["policy", "allow", "network", "--sandbox", name, r.host]);
        } catch (e) { failed.push(`${r.host}: ${e.message}`); }
      }
      if (failed.length) notify({ title: "Sandbox", body: failed.join("\n"), level: "error" });
      else notify({ title: `Allowed for ${name}`, body: todo.map(r => r.host).join(", "), level: "success" });
      this.loadNet(cx);
    });
  }

  // 許可待ちを断るか、この sandbox の rule を消す
  revoke(row, cx) {
    const args = row.approval && row.state === "pending" ? ["policy", "approval", "respond", row.approval.id, "--option", "dismiss"]
      : row.own ? ["policy", "rm", "network", "--sandbox", this.name, "--id", row.rule.id] : null;
    if (!args) return;
    this.load(cx, "allow", async cx => {
      try { await this.sbx(args); }
      catch (e) { notify({ title: "Sandbox", body: String(e.message), level: "error" }); }
      this.loadNet(cx);
    });
  }

  // ---- Metrics

  loadMetrics(cx) {
    this.load(cx, "metrics", async (cx, name) => {
      const r = await exec("sbx", ["exec", name, "sh", "-c", METRICS], { on: this.loc.on });
      if (r.code !== 0) throw new Error(r.stderr.trim().split("\n").pop() || "Cannot read metrics");
      if (name !== this.name) return;
      const [head, tail = ""] = r.stdout.split("\n---\n"), lines = head.split("\n");
      const cpu = line => { const n = line.trim().split(/\s+/).slice(1).map(Number); return { idle: n[3] + n[4], total: n.reduce((a, b) => a + b, 0) }; };
      const a = cpu(lines[0]), b = cpu(lines[1]);
      const kb = name => Number(lines.find(line => line.startsWith(name))?.split(/\s+/)[1] ?? 0) * 1024;
      const disk = lines[lines.length - 1].trim().split(/\s+/);
      const total = kb("MemTotal:"), free = kb("MemAvailable:");
      this.metrics = {
        cpu: b.total > a.total ? 1 - (b.idle - a.idle) / (b.total - a.total) : 0, cores: Number(lines[2]), load: lines[3].split(" ").slice(0, 3),
        mem: { used: total - free, total }, disk: { used: Number(disk[2]) * 1024, total: Number(disk[1]) * 1024 },
        top: tail.trim().split("\n").slice(1).map(line => { const [pcpu, rss, pid, ...args] = line.trim().split(/\s+/); return { pcpu: Number(pcpu), rss: Number(rss) * 1024, pid, args: args.join(" ") }; })
          // 測るために自分で動かした物は出さない
          .filter(p => !p.args.includes("/proc/stat") && !p.args.startsWith("ps -eo pcpu") && p.args !== "head -9"),
      };
      this.history = [...this.history, { cpu: this.metrics.cpu, mem: total ? (total - free) / total : 0 }].slice(-HISTORY);
    });
  }

  // ---- keys

  rows() { return this.tab === "ports" ? this.portRows() : this.tab === "network" ? this.netRows() : []; }

  selected(rows = this.rows()) {
    const list = rows.filter(r => !r.head);
    return list.find(r => r.key === this.sel[this.tab]) ?? list[0] ?? null;
  }

  move(step, cx) {
    if (this.tab === "files") {
      const list = this.entries(), at = list.indexOf(this.current());
      const to = list[Math.min(list.length - 1, Math.max(0, at + step))];
      if (!to) return;
      this.at.set(this.dir, to.name);
      this.scroll.files.scroll_to_item(list.indexOf(to), "center");
      this.sync(cx);
    } else {
      const rows = this.rows(), list = rows.filter(r => !r.head), at = list.indexOf(this.selected(rows));
      const to = list[Math.min(list.length - 1, Math.max(0, at + step))];
      if (!to) return;
      this.sel[this.tab] = to.key;
      this.scroll[this.tab].scroll_to_item(rows.indexOf(to), "center");
    }
  }

  // 入力欄を開く (mode と、開いた key)、または閉じる。keep は絞り込みを残して閉じる印
  type(mode, cx, keep) {
    const was = this.typing;
    this.typing = mode;
    if (mode) {
      this.opening = mode === "filter" ? "/" : "a";
      this.input.set_value(mode === "filter" ? this.filter[this.tab] ?? "" : "");
      this.input.focus();
    } else {
      if (was === "filter" && !keep && this.filter[this.tab]) { this.filter[this.tab] = ""; this.sync(cx); }
      if (was) this.handle.focus();
    }
    cx.notify();
  }

  key(e, cx) {
    if (e.modifiers.control || e.modifiers.alt || e.modifiers.platform) return;
    const k = e.key, shift = e.modifiers.shift, tab = this.tab;
    if (this.typing) {
      if (k === "escape") this.type(null, cx);
      else if (k === "down") this.move(1, cx);
      else if (k === "up") this.move(-1, cx);
      else return;
      cx.notify();
      return cx.stop_propagation();
    }
    const row = tab === "ports" || tab === "network" ? this.selected() : null;
    if (k === "escape" && this.filter[tab]) { this.filter[tab] = ""; this.sync(cx); }
    else if (k === "escape" || k === "q") closeOverlay(props().overlay);
    else if (k >= "1" && k <= "4" && !shift) this.show(TABS[Number(k) - 1], cx);
    else if (k === "tab") this.show(TABS[(TABS.indexOf(tab) + (shift ? TABS.length - 1 : 1)) % TABS.length], cx);
    else if (k === "]" || k === "[") this.cycle(k === "]" ? 1 : -1, cx);
    else if (k === "r") this.refresh(cx);
    else if (k === "j" || k === "down") this.move(1, cx);
    else if (k === "k" || k === "up") this.move(-1, cx);
    else if (k === "g") this.move(shift ? Infinity : -Infinity, cx);
    else if (k === "/" && (tab === "files" || tab === "network")) this.type("filter", cx);
    else if (tab === "files") {
      const file = this.current();
      if (k === "l" || k === "right" || k === "enter") this.enter(cx);
      else if (k === "h" || k === "left" || k === "backspace") this.leave(cx);
      else if (k === ".") { this.hidden = !this.hidden; this.sync(cx); }
      else if (k === "m") this.raw = !this.raw;
      else if (k === "d" || k === "s") this.save(cx);
      else if (k === "y" && file) { cx.write_to_clipboard(file.path); notify({ title: "Sandbox", body: `Copied ${file.path}`, timeout: 2000 }); }
      else return;
    } else if (tab === "ports") {
      const url = row?.port ? `http://localhost:${row.port.host_port}` : null;
      if (k === "a") this.type("port", cx);
      else if ((k === "enter" || k === "o") && url) cx.open_url(url);
      else if (k === "enter" && row?.listen) this.publish(`${row.listen}:${row.listen}`, cx);
      else if (k === "y" && url) { cx.write_to_clipboard(url); notify({ title: "Sandbox", body: `Copied ${url}`, timeout: 2000 }); }
      else if ((k === "d" || k === "x") && row?.port) this.unpublish(row.port, cx);
      else return;
    } else if (tab === "network") {
      if (k === "a" && shift) this.allow(this.netRows(), cx);
      else if ((k === "a" || k === "enter") && row) this.allow([row], cx);
      else if ((k === "d" || k === "x") && row) this.revoke(row, cx);
      else if (k === "y" && row) cx.write_to_clipboard(row.host ?? row.pass?.host ?? row.rule.resources.join(","));
      else return;
    } else return;
    cx.stop_propagation();
    cx.notify();
  }

  // ---- 描画

  // virtual list の renderer の中では on_click 等の handler を登録できない。click は list 側の on_item_click で受ける
  line(t, on) {
    return h_flex().h(ROW).px(8).gap(8).items_center().rounded(7).cursor_pointer().when(on, el => el.bg(t.selected)).hover(s => s.bg(t.hover));
  }

  head(t, text) { return h_flex().h(ROW).px(8).items_center().text_size(11).font_semibold().text_color(t.muted).child(text); }

  table(t, id, rows, key, render, click) {
    return div().flex_1().min_h(0).relative()
      .child(v_virtual_list(id, rows.length, ROW, i => key(rows[i]), range => rows.slice(range.start, range.end).map(render))
        .track_scroll(this.scroll[this.tab]).size_full().px(6)
        .on_item_click((key, cx) => { click(key, cx); this.handle.focus(); cx.notify(); }))
      .child(Scrollbar.vertical(id).absolute().inset_0());
  }

  field(t, hint) {
    return h_flex().flex_none().p(6).gap(8).items_center()
      .child(div().flex_none().text_size(11).text_color(t.dim).child(hint))
      .child(Input.new(this.input).flex_1().h(30).px(8).rounded(7).border_1().border_color(this.typing ? t.accent : t.border).bg(t.background).text_size(12).text_color(t.foreground));
  }

  note(t, text) { return div().p(16).text_color(t.dim).child(text); }

  files(t) {
    const here = this.dirs.get(this.dir), list = this.entries(), cur = this.current();
    const filtering = this.typing === "filter" || Boolean(this.filter.files);
    return h_flex().flex_1().min_h(0).items_start()
      .child(v_flex().w(360).h_full().flex_none().border_r(1).border_color(t.border)
        .child(h_flex().h(30).flex_none().px(14).items_center().border_b(1).border_color(t.border).text_size(11).text_color(t.dim).child(div().min_w(0).truncate().child(this.dir ?? "")))
        .when(filtering, el => el.child(this.field(t, "Filter")))
        .child(list.length
          ? this.table(t, "sb-files", list, e => e.path, e => this.line(t, e === cur)
              .child(div().flex_1().min_w(0).truncate().when(e.dir, el => el.text_color(t.accent)).child(e.dir ? `${e.name}/` : e.name))
              .child(div().flex_none().text_size(11).text_color(t.dim).child(e.dir ? "" : bytes(e.size)))
              .child(div().w(26).flex_none().text_size(11).text_color(t.dim).child(ago(e.mtime))),
            (path, cx) => { const e = list.find(e => e.path === path); if (e) { this.at.set(this.dir, e.name); this.sync(cx); } })
          : this.note(t, here?.error ?? (!here ? "Loading…" : this.filter.files ? "No files match the filter" : this.hidden ? "Empty folder" : "Nothing here · press . for hidden files")))
        .when(Boolean(here?.more), el => el.child(div().flex_none().px(14).py(4).text_size(11).text_color(t.dim).child(`Showing the first ${MAX_ENTRIES} entries`))))
      .child(this.preview_pane(t, cur).h_full());
  }

  // 領域に収まる大きさで置く。元の大きさより拡げない。透過した画像は白地を前提にした物が多いので、下に白を敷く
  drawing(p) {
    const area = this.area ?? { width: 800, height: 600 };
    const scale = Math.max(0.01, Math.min((area.width - 2 * PAD) / p.width, (area.height - 2 * PAD) / p.height, 1));
    const w = Math.round(p.width * scale), h = Math.round(p.height * scale);
    return div().id("sb-picture").flex_1().min_h(0).w_full().flex().items_center().justify_center().overflow_hidden()
      .on_size_change((size, cx) => { this.area = size; cx.notify(); })
      .child(div().w(w).h(h).flex_none().bg("#ffffff").child(image(p.name).w(w).h(h)));
  }

  preview_pane(t, e) {
    if (!e) return v_flex().flex_1().min_w(0);
    const inner = e.dir ? this.dirs.get(e.path) : null, kids = e.dir ? this.entries(e.path) : [];
    const body = e.dir
      ? (kids.length
        ? v_flex().id(`sb-kids-${e.path}`).flex_1().min_h(0).overflow_y_scrollbar().px(14).py(8).gap(2).text_size(12)
          .children(kids.slice(0, 200).map(k => div().truncate().text_color(k.dir ? t.accent : t.muted).child(k.dir ? `${k.name}/` : k.name)))
        : this.note(t, inner?.error ?? (inner ? "Empty folder" : "Loading…")))
      : this.shown?.path !== e.path ? this.note(t, "Loading file…")
      : this.picture ? this.drawing(this.picture)
      : this.code === null ? this.note(t, this.why || "Loading file…")
      : this.markdown && !this.raw ? v_flex().id("sb-markdown").flex_1().min_h(0).overflow_y_scrollbar().px(20).py(14).text_size(13).child(TextView.markdown(`sb-md-${e.path}`, this.text).selectable(true))
      : Editor.new(this.code).flex_1().min_h(0);
    return v_flex().flex_1().min_w(0).min_h(0)
      .child(h_flex().h(30).flex_none().px(14).gap(10).items_center().border_b(1).border_color(t.border).text_size(11).text_color(t.dim)
        .child(div().flex_1().min_w(0).truncate().child(e.path))
        .child(div().flex_none().child(`${e.dir ? "folder" : bytes(e.size)} · ${new Date(e.mtime).toLocaleString()}`)))
      .child(body);
  }

  portsView(t) {
    const rows = this.portRows(), sel = this.selected(rows);
    if (this.ports === null) return this.note(t, this.error.ports ?? "Loading…");
    return v_flex().flex_1().min_h(0)
      .when(this.typing === "port", el => el.child(this.field(t, "Publish [HOST_PORT:]SANDBOX_PORT[/PROTOCOL]")))
      .child(this.table(t, "sb-ports", rows, r => r.key, r => r.head ? this.head(t, r.head)
        : r.port ? this.line(t, r === sel)
          .child(div().w(8).h(8).flex_none().rounded(4).bg(t.ansi2))
          .child(div().w(220).flex_none().truncate().child(`${r.port.host_ip}:${r.port.host_port}`))
          .child(div().flex_none().text_color(t.dim).child("→"))
          .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(`${r.port.sandbox_port}/${r.port.protocol}`))
          .child(div().flex_none().text_size(11).text_color(t.dim).child(`http://localhost:${r.port.host_port}`))
        : this.line(t, r === sel)
          .child(div().w(8).h(8).flex_none().rounded(4).border_1().border_color(t.dim))
          .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(`:${r.listen}`))
          .child(div().flex_none().text_size(11).text_color(t.dim).child("not published · Enter to publish")),
        key => { if (!key.startsWith("head:")) this.sel.ports = key; }))
      .when(!this.ports.length && !this.listening.length, el => el.child(this.note(t, "No published ports · press a to publish one")));
  }

  network(t) {
    const rows = this.netRows(), sel = this.selected(rows);
    if (this.net === null) return this.note(t, this.error.network ?? "Loading…");
    const color = { pending: t.ansi3, blocked: t.ansi1, allowed: t.ansi2 };
    const label = { pending: "waiting for approval", blocked: "blocked", allowed: "allowed now" };
    const filtering = this.typing === "filter" || Boolean(this.filter.network);
    return v_flex().flex_1().min_h(0)
      .when(filtering, el => el.child(this.field(t, "Search")))
      .child(rows.length ? this.table(t, "sb-net", rows, r => r.key, r => r.head ? this.head(t, r.head)
        : r.host ? this.line(t, r === sel)
          .child(div().w(8).h(8).flex_none().rounded(4).bg(color[r.state]))
          .child(div().flex_1().min_w(0).truncate().child(r.host))
          .child(div().flex_none().text_size(11).text_color(color[r.state]).child(label[r.state]))
          .child(div().w(50).flex_none().text_size(11).text_color(t.dim).child(r.count ? `×${r.count}` : ""))
          .child(div().w(26).flex_none().text_size(11).text_color(t.dim).child(ago(r.last)))
        : r.pass ? this.line(t, r === sel)
          .child(div().w(8).h(8).flex_none().rounded(4).bg(t.ansi2))
          .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(r.pass.host))
          .child(div().w(50).flex_none().text_size(11).text_color(t.dim).child(`×${r.pass.count}`))
          .child(div().w(26).flex_none().text_size(11).text_color(t.dim).child(ago(r.last)))
        : this.line(t, r === sel)
          .child(div().w(40).flex_none().text_size(11).text_color(r.rule.decision === "allow" ? t.ansi2 : t.ansi1).child(r.rule.decision))
          .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(r.rule.resources.join(", ")))
          .child(div().flex_none().text_size(11).text_color(t.dim).child(r.own ? "this sandbox" : r.rule.scope)),
        key => { if (!key.startsWith("head:")) this.sel.network = key; })
        : this.note(t, this.filter.network ? "No hosts match the search" : "No network activity yet"));
  }

  bar(t, label, value, detail, pick) {
    const tint = value >= 0.9 ? t.ansi1 : value >= 0.7 ? t.ansi3 : t.accent, max = 36;
    return v_flex().flex_1().min_w(0).p(14).gap(8).rounded(10).border_1().border_color(t.border).bg(t.background)
      .child(h_flex().items_center().child(div().flex_1().text_size(11).font_semibold().text_color(t.muted).child(label)).child(div().text_size(11).text_color(t.dim).child(detail)))
      .child(div().text_size(22).font_semibold().child(`${Math.round(value * 100)}%`))
      .child(div().h(6).rounded(3).bg(t.border).child(div().h(6).rounded(3).bg(tint).w(`${Math.round(Math.min(1, Math.max(0, value)) * 100)}%`)))
      .when(Boolean(pick), el => el.child(h_flex().h(max).gap(2).items_end().children(
        this.history.map(h => div().w(3).flex_none().rounded(1).bg(t.dim).h(Math.max(1, Math.round(pick(h) * max)))))))
      // 履歴の無い tile も、隣と同じ高さにする
      .when(!pick, el => el.child(div().h(max)));
  }

  metricsView(t) {
    const m = this.metrics, net = this.net?.log;
    if (!m) return this.note(t, this.error.metrics ?? "Loading…");
    return v_flex().id("sb-metrics").flex_1().min_h(0).overflow_y_scrollbar().p(16).gap(14)
      .child(h_flex().gap(14)
        .child(this.bar(t, "CPU", m.cpu, `${m.cores} cores · load ${m.load.join(" ")}`, h => h.cpu))
        .child(this.bar(t, "Memory", m.mem.total ? m.mem.used / m.mem.total : 0, `${bytes(m.mem.used)} / ${bytes(m.mem.total)}`, h => h.mem))
        .child(this.bar(t, "Disk /", m.disk.total ? m.disk.used / m.disk.total : 0, `${bytes(m.disk.used)} / ${bytes(m.disk.total)}`)))
      .when(Boolean(net), el => el.child(div().text_size(12).text_color(t.dim).child(
        `Network: ${(net.allowed ?? []).reduce((n, a) => n + a.count, 0)} allowed · ${(net.blocked ?? []).reduce((n, b) => n + b.count, 0)} blocked requests`)))
      .child(v_flex().gap(2)
        .child(h_flex().h(24).px(8).gap(10).items_center().text_size(11).font_semibold().text_color(t.muted)
          .child(div().w(50).flex_none().child("CPU %")).child(div().w(70).flex_none().child("Memory")).child(div().w(60).flex_none().child("PID")).child("Command"))
        .children(m.top.map(p => h_flex().h(24).px(8).gap(10).items_center().text_size(12)
          .child(div().w(50).flex_none().child(p.pcpu.toFixed(1))).child(div().w(70).flex_none().text_color(t.muted).child(bytes(p.rss)))
          .child(div().w(60).flex_none().text_color(t.dim).child(p.pid)).child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(p.args)))));
  }

  hint() {
    const common = "1-4 view · [ ] sandbox · r reload · q close";
    if (this.tab === "files") return `hjkl move · / filter · . hidden${this.markdown ? " · m raw" : ""} · d copy to host · y copy path · ${common}`;
    if (this.tab === "ports") return `j/k move · a publish · Enter open · y copy URL · d unpublish · ${common}`;
    if (this.tab === "network") return `j/k move · / search · a allow for this sandbox · A allow all listed · d dismiss / remove rule · ${common}`;
    return common;
  }

  render() {
    const t = theme(), box = this.box(), boxes = this.boxes ?? [];
    const stopped = box && box.status !== "running" && (this.tab === "files" || this.tab === "metrics");
    const body = this.boxes === null ? this.note(t, this.error.boxes ?? "Loading…")
      : !box ? this.note(t, this.error.boxes ?? `No sandboxes${this.loc.on ? ` on ${this.loc.on}` : ""} · create one with sbx create`)
      : stopped ? this.note(t, `${box.name} is ${box.status} · start it with sbx run to look inside`)
      : this.tab === "files" ? this.files(t) : this.tab === "ports" ? this.portsView(t) : this.tab === "network" ? this.network(t) : this.metricsView(t);
    const waiting = this.netRows().filter(r => r.state === "pending").length;
    // dialog の枠は角丸だが、中身は角丸に切り抜かれない。背景も同じ丸みにして、角からはみ出させない
    return v_flex().id("sandbox").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .size_full().min_h(0).rounded(10).bg(t.popover).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(10).items_center().border_b(1).border_color(t.border)
        .child(div().flex_none().font_semibold().child("Sandbox"))
        .when(Boolean(box), el => el
          .child(div().w(8).h(8).flex_none().rounded(4).bg(box.status === "running" ? t.ansi2 : t.dim))
          .child(div().flex_none().max_w(260).truncate().child(box.name))
          .child(div().flex_none().text_size(11).text_color(t.dim).child(`${box.agent} · ${box.status}${boxes.length > 1 ? ` · ${boxes.indexOf(box) + 1}/${boxes.length}` : ""}`)))
        .child(div().w(8))
        .children(TABS.map((tab, i) => div().id(`sb-tab-${tab}`).flex_none().px(8).h(24).flex().items_center().rounded(6).text_size(12).cursor_pointer()
          .text_color(tab === this.tab ? t.foreground : t.muted).when(tab === this.tab, el => el.bg(t.selected)).hover(s => s.bg(t.hover))
          .on_click((_e, cx) => { this.show(tab, cx); this.handle.focus(); })
          .child(`${i + 1} ${TITLE[tab]}${tab === "network" && waiting ? ` (${waiting})` : ""}`)))
        .child(div().flex_1())
        .child(div().min_w(0).truncate().text_size(11).text_color(t.dim).child(this.hint())))
      .child(body);
  }
}
