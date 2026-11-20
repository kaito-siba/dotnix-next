// sbx (Docker Sandboxes) の sandbox を見る dialog。Files / Ports / Network / Metrics の 4 面がある
// Files は sandbox の中を yazi のように hjkl で辿り、preview して、host へコピーする。辿る所は explorer と同じ物 (./browser.js)
// Ports は host への port の公開、Network は遮断された通信を探して sandbox 単位で許可する
// sandbox は microVM なので、中の事は全て sbx exec 越しに調べる。sbx exec は止まっている sandbox を起動してしまうので、動いている物にしか使わない
import { View, div } from "gpui-kit";
import { v_flex, h_flex, Scrollbar, v_virtual_list, VirtualListScrollHandle, InputState, Input } from "gpui-base";
import { spaces, panes, focused, exec, notify, theme, props, closeOverlay, nextCommand } from "herdr";
import { Browser, LIST, parse, join, ago, bytes } from "./browser.js";

const TABS = ["files", "ports", "network", "metrics"];
const TITLE = { files: "Files", ports: "Ports", network: "Network", metrics: "Metrics" };
const ROW = 28, POLL = 5000, HISTORY = 60;
// image() は app home からの相対 path しか読めないので、見せる画像はここへコピーする
const COPIES = "sandbox/preview";
// CPU の使用率は /proc/stat の差から出すので、間を空けて 2 回読む
const METRICS = `head -1 /proc/stat; sleep 0.5; head -1 /proc/stat; nproc; cat /proc/loadavg
grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; df -kP / | tail -1
echo ---; ps -eo pcpu,rss,pid,args --sort=-pcpu 2>/dev/null | head -9`;
// Esc の action を、on_key_down と同じ key() で扱うための key event
const ESCAPE = { key: "escape", keystroke: "escape", modifiers: {} };
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
const last = text => text.trim().split("\n").pop();

export default class Sandbox extends View {
  init(_props, cx) {
    this.loc = location();
    // boxes の null は取っている途中の印
    this.boxes = null; this.name = null; this.tab = "files";
    this.busy = {}; this.error = {};
    this.sel = { ports: null, network: null };
    // Files の絞り込みは browser が持つ
    this.filter = { network: "" };
    // typing は入力欄の使い道: filter (絞り込み) か port (公開する port)。null は入力していない
    this.typing = null;
    this.input = InputState.new({ placeholder: "" });
    this.input.on("change", (_e, cx) => {
      // 入力欄を開いた key がそのまま入力される事があるので捨てる
      if (this.opening && this.input.value() === this.opening) { this.opening = null; this.input.set_value(""); return; }
      this.opening = null;
      if (this.typing === "filter") { this.filter[this.tab] = this.input.value(); cx.notify(); }
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
    // Esc は app が key context の Overlay で overlay.close に束ねていて、on_key_down に届く前に dialog を閉じる。より深い key context に束ねた action で先に受ける
    // herdr は keys を読み直すたびに全ての束ねを消すので、開くたびに束ね直す。render の中では束ねられない
    try { cx.bind_keys([{ keystroke: "escape", action: "sandbox_escape", context: "SandboxDialog" }]); } catch {}
    cx.spawn(async cx => { await Browser.sweep(COPIES); this.refresh(cx); });
  }

  async close() { await this.browser?.close(); }

  // sandbox ごとの状態。sandbox を切り替えたら捨てる
  reset() {
    this.browser?.close(); this.browser = null;
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
    if (tab === "files" && this.running()) this.browser?.reload(cx);
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
    const on = this.loc.on;
    this.browser = new Browser({
      id: "sb", copies: COPIES, dir: host ? inside(host) + cwd.slice(host.split(":")[0].length) : roots[0] ?? "/", focus: () => this.handle.focus(),
      source: {
        list: async dir => {
          const r = await exec("sbx", ["exec", name, "sh", "-c", LIST, "ls", dir], { on });
          return r.code === 0 ? { entries: parse(r.stdout, dir) } : { error: r.code === 3 ? "Cannot open this folder" : last(r.stderr) || "Cannot list this folder" };
        },
        read: async (path, max) => {
          const r = await exec("sbx", ["exec", name, "head", "-c", String(max), path], { on });
          return r.code === 0 ? { text: r.stdout } : { note: last(r.stderr) || "Cannot read this file" };
        },
        // 他の machine の sandbox からは app home へコピーできないので、画像としては出さない
        fetch: on ? null : async (path, dest) => (await exec("sbx", ["cp", `${name}:${path}`, dest])).code === 0,
      },
    });
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

  // 選んでいる file か folder を、host の ~/Downloads/sbx/<sandbox>/ へコピーする。置いた path は clipboard に入れる
  save(cx) {
    const e = this.browser?.current();
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

  move(step) {
    const rows = this.rows(), list = rows.filter(r => !r.head), at = list.indexOf(this.selected(rows));
    const to = list[Math.min(list.length - 1, Math.max(0, at + step))];
    if (!to) return;
    this.sel[this.tab] = to.key;
    this.scroll[this.tab].scroll_to_item(rows.indexOf(to), "center");
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
      if (was === "filter" && !keep && this.filter[this.tab]) this.filter[this.tab] = "";
      if (was) this.handle.focus();
    }
    cx.notify();
  }

  key(e, cx) {
    if (e.modifiers.control || e.modifiers.alt || e.modifiers.platform) return;
    const k = e.key, shift = e.modifiers.shift, tab = this.tab;
    // Files を出している間は、辿る key と絞り込みを browser が受ける
    if (tab === "files" && this.running() && this.browser?.key(e, cx)) return;
    if (this.typing) {
      if (k === "escape") this.type(null, cx);
      else if (k === "down") this.move(1, cx);
      else if (k === "up") this.move(-1, cx);
      else return;
      cx.notify();
      return cx.stop_propagation();
    }
    const row = tab === "ports" || tab === "network" ? this.selected() : null;
    if (k === "escape" && this.filter[tab]) this.filter[tab] = "";
    // 入力欄を mouse で押した後や、入力欄が先に focus を手放した後の Esc では、dialog が focus を持っていない。閉じずに focus を取り戻す
    else if (k === "escape" && !this.handle.is_focused()) this.handle.focus();
    else if (k === "escape" || k === "q") closeOverlay(props().overlay);
    else if (k >= "1" && k <= "4" && !shift) this.show(TABS[Number(k) - 1], cx);
    else if (k === "tab") this.show(TABS[(TABS.indexOf(tab) + (shift ? TABS.length - 1 : 1)) % TABS.length], cx);
    else if (k === "]" || k === "[") this.cycle(k === "]" ? 1 : -1, cx);
    else if (k === "r") this.refresh(cx);
    else if (k === "j" || k === "down") this.move(1, cx);
    else if (k === "k" || k === "up") this.move(-1, cx);
    else if (k === "g") this.move(shift ? Infinity : -Infinity, cx);
    else if (k === "/" && tab === "network") this.type("filter", cx);
    else if (tab === "files") {
      if (k === "s") this.save(cx);
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
    if (this.tab === "files") return `${this.browser?.hint() ?? ""} · s save to host · ${common}`;
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
      : this.tab === "files" ? this.browser.render(t) : this.tab === "ports" ? this.portsView(t) : this.tab === "network" ? this.network(t) : this.metricsView(t);
    const waiting = this.netRows().filter(r => r.state === "pending").length;
    // dialog の枠は角丸だが、中身は角丸に切り抜かれない。背景も同じ丸みにして、角からはみ出させない
    return v_flex().id("sandbox").key_context("SandboxDialog").on_action("sandbox_escape", (_e, cx) => this.key(ESCAPE, cx))
      .track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
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
