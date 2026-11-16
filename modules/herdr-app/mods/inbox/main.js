// 自分の手を待っている物を 1 か所に並べる右 panel
// 許可や返事を待っている agent、見ていない間に終わった agent、自分の branch の pull request で落ちた CI、自分宛の review 依頼
// agent の状態は app の live data から、GitHub の事は gh から取る。gh は開いている間ずっと数分おきに呼ぶ
// Slack の依頼と standup の下書きは、常駐機の work-digest の API から読む (modules/work-digest)。URL が決まっている machine でだけ出す
// 件数は shared の "inbox.count" に、pull request の状態は "inbox.github" に置く (tab bar のボタンと tasks mod が読む)
import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { spaces, panes, agents, exec, hc, run, theme, shared, setShared } from "herdr";
// work-digest の API の URL。使わない machine では null (nix が書く: ../../herdr-app.nix)
import { WORK_DIGEST } from "./env.js";

const TICK = 60000, PULLS = 3 * 60000, REVIEWS = 5 * 60000, MAX_REPOS = 12;
// sweep や下書きが走っている間は、終わるのを早めに見に行く
const DIGEST = 60000, DIGEST_BUSY = 10000;
const FAILED = new Set(["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"]);
const TRUNK = new Set(["main", "master", "develop", "trunk"]);

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function ago(ms) {
  const s = Math.max(0, (Date.now() - ms) / 1000);
  if (s < 60) return "now";
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}

// 止まっている agent の画面の最後の数行。たいていは質問か、許可を求める prompt
// 質問とその選択肢が続いている時は、質問から始める
function snippet(text) {
  const lines = (text ?? "").split("\n")
    .map(l => l.replace(/[│─╭╮╰╯┌┐└┘├┤┬┴┼═║▔▁▏▕]/g, " ").replace(/\s+/g, " ").trim())
    .filter(l => /[\p{L}\p{N}]/u.test(l));
  const tail = lines.slice(-8), asked = tail.findLastIndex(l => /[?？]$/.test(l));
  return (asked >= 0 ? tail.slice(asked) : lines.slice(-4)).join(" · ").slice(0, 240);
}

// GitHub Actions 等の check run と、外部の CI が付ける commit status の 2 種類がある
function checks(rollup) {
  const failed = [];
  let pending = false;
  for (const c of rollup ?? []) {
    const result = (c.conclusion || c.state || "").toUpperCase();
    if (FAILED.has(result)) failed.push({ name: c.name || c.context || "check", url: c.detailsUrl || c.targetUrl || null });
    else if (c.__typename === "CheckRun" && (c.status || "").toUpperCase() !== "COMPLETED" || result === "PENDING" || result === "EXPECTED") pending = true;
  }
  return { ci: !rollup?.length ? "none" : failed.length ? "fail" : pending ? "pending" : "pass", failed };
}

export default class Inbox extends View {
  init(_props, cx) {
    this.snips = {}; this.reviews = []; this.error = null;
    this.busy = false; this.pulledAt = 0; this.reviewedAt = 0;
    cx.timer.every(TICK, cx => this.tick(cx));
    this.tick(cx);
    // digest の null は取っている途中か、使わない machine の印
    this.digest = null; this.digestError = null; this.digestAt = 0; this.asking = false;
    if (WORK_DIGEST) {
      cx.timer.every(DIGEST_BUSY, cx => {
        const busy = this.digest?.slack.running || this.digest?.standup.running;
        if (busy || Date.now() - this.digestAt >= DIGEST) this.ask(cx);
      });
      this.ask(cx);
    }
  }

  // work-digest に聞く。path が無ければ状態を読むだけ。状態を変える call は、変えた後の状態か、始めた事だけを返す
  ask(cx, path, body) {
    if (this.asking && !path) return;
    this.asking = true;
    cx.spawn(async cx => {
      try {
        if (path) {
          const r = await fetch(`${WORK_DIGEST}${path}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body ?? {}) });
          if (!r.ok) throw new Error((await r.json().catch(() => null))?.error ?? `work-digest answered ${r.status}`);
        }
        const r = await fetch(`${WORK_DIGEST}/state`);
        if (!r.ok) throw new Error((await r.json().catch(() => null))?.error ?? `work-digest answered ${r.status}`);
        this.digest = await r.json(); this.digestError = null;
      } catch (e) { this.digestError = String(e?.message ?? e); }
      finally { this.asking = false; this.digestAt = Date.now(); cx.notify(); }
    });
  }

  chip(t, id, label, action) {
    return div().id(id).flex_none().px(7).h(20).flex().items_center().rounded(5).border_1().border_color(t.border).text_size(11).text_color(t.muted).cursor_pointer()
      .hover(s => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => { cx.stop_propagation(); action(cx); }).child(label);
  }

  // Slack の依頼と FYI。click で Slack の message を開く。Done は片付けた、Skip は見送る、Seen は FYI を読んだ印
  slack(t, item) {
    const ask = item.kind === "ask", ids = [item.permalink];
    return v_flex().id(`in-s-${item.permalink}`).px(10).py(8).gap(5).rounded(8).border_1().border_color(item.urgent ? t.blocked : t.border).bg(t.raised).cursor_pointer()
      .hover(s => s.border_color(t.accent)).on_click((_e, cx) => cx.open_url(item.permalink))
      .child(h_flex().gap(8).items_center()
        .child(div().size(8).flex_none().rounded(4).bg(item.urgent ? t.blocked : ask ? t.accent : t.dim))
        .child(div().flex_1().min_w(0).truncate().font_medium().child(item.from))
        .child(div().flex_none().max_w(140).truncate().text_size(11).text_color(t.dim).child(item.channel)))
      .child(div().text_size(12).text_color(t.muted).child(item.text))
      .child(h_flex().gap(6).items_center()
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(item.due ? t.working : t.dim).child(item.due || ago(item.at)))
        .when(ask, el => el.child(this.chip(t, `in-s-done-${item.permalink}`, "Done", cx => this.ask(cx, "/slack/items", { op: "tick", ids })))
          .child(this.chip(t, `in-s-skip-${item.permalink}`, "Skip", cx => this.ask(cx, "/slack/items", { op: "skip", ids }))))
        .when(!ask, el => el.child(this.chip(t, `in-s-seen-${item.permalink}`, "Seen", cx => this.ask(cx, "/slack/items", { op: "skip", ids })))));
  }

  // standup の下書き。Copy は Slack 等にそのまま貼れる箇条書きで clipboard に入れる
  standup(t, d) {
    const text = d.bullets.map(b => `- ${b}`).join("\n");
    return v_flex().flex_none().px(12).py(10).gap(6).border_t(1).border_color(t.border).bg(t.chrome)
      .child(h_flex().gap(6).items_center()
        .child(div().flex_1().min_w(0).truncate().text_size(11).font_semibold().text_color(t.muted)
          .child(`Standup${d.day ? ` · ${d.label} ${d.day}` : ""}${d.running ? " · writing…" : d.writtenAt ? ` · ${ago(d.writtenAt)}` : ""}`))
        .when(Boolean(d.bullets.length), el => el.child(this.chip(t, "in-su-copy", this.copied === text ? "Copied" : "Copy", cx => { cx.write_to_clipboard(text); this.copied = text; cx.notify(); })))
        .when(!d.running, el => el.child(this.chip(t, "in-su-write", "Write now", cx => this.ask(cx, "/standup/write")))))
      .when(Boolean(d.error), el => el.child(div().text_size(11).text_color(t.blocked).child(d.error)))
      .child(d.bullets.length
        ? v_flex().id("in-su-body").max_h(200).overflow_y_scrollbar().gap(3).children(d.bullets.map(b => h_flex().gap(6).items_start().text_size(12)
          .child(div().flex_none().text_color(t.dim).child("•")).child(div().flex_1().min_w(0).child(b))))
        : div().text_size(12).text_color(t.dim).child(d.running ? "" : "No draft yet"));
  }

  tick(cx, now) {
    if (this.busy) return;
    const pulls = now || Date.now() - this.pulledAt >= PULLS, reviews = now || Date.now() - this.reviewedAt >= REVIEWS;
    if (!pulls && !reviews) return;
    this.busy = true;
    cx.spawn(async cx => {
      try {
        if (pulls) { await this.pulls(); this.pulledAt = Date.now(); }
        if (reviews) { await this.requests(); this.reviewedAt = Date.now(); }
      } finally { this.busy = false; cx.notify(); }
    });
  }

  // 開いている pane の branch ごとに、その pull request と CI を見る。main 等の幹の branch は見ない
  async pulls() {
    const seen = new Set(), repos = [];
    for (const space of spaces()) {
      for (const pane of panes()) {
        if (!pane.terminal || !pane.cwd || !pane.branch || TRUNK.has(pane.branch) || !space.tabs.some(tab => tab.id === pane.tab)) continue;
        const key = `${space.machine ?? ""}|${pane.cwd}`;
        if (!seen.has(key) && seen.size < MAX_REPOS) { seen.add(key); repos.push({ cwd: pane.cwd, on: space.machine }); }
      }
    }
    const found = await Promise.all(repos.map(async ({ cwd, on }) => {
      try {
        const r = await exec("gh", ["pr", "view", "--json", "number,title,url,state,headRefName,statusCheckRollup"], { cwd, on });
        if (r.code !== 0) return null;
        const pr = JSON.parse(r.stdout);
        return pr.state === "OPEN" ? { number: pr.number, title: pr.title, url: pr.url, branch: pr.headRefName, ...checks(pr.statusCheckRollup) } : null;
      } catch { return null; }
    }));
    // 同じ pull request を別の folder (worktree 等) からも見ている事がある
    const prs = [...new Map(found.filter(Boolean).map(pr => [pr.url, pr])).values()].sort((a, b) => a.url.localeCompare(b.url));
    if (!same(prs, shared("inbox.github")?.prs)) setShared("inbox.github", { prs });
  }

  async requests() {
    try {
      const r = await exec("gh", ["search", "prs", "--review-requested=@me", "--state=open", "--limit", "20", "--json", "number,title,url,repository,updatedAt"]);
      if (r.code !== 0) throw new Error(r.stderr.trim().split("\n")[0] || "gh failed");
      this.reviews = JSON.parse(r.stdout);
      this.error = null;
    } catch (e) { this.error = String(e?.message ?? e); }
  }

  // agent が止まった時に一度だけ、その画面を読む。動き出したら捨てる
  read(cx, blocked) {
    for (const address of Object.keys(this.snips)) if (!blocked.some(a => a.address === address)) delete this.snips[address];
    for (const a of blocked) {
      if (a.address in this.snips) continue;
      this.snips[a.address] = "";
      cx.spawn(async cx => {
        const r = await hc(["read", a.address, "--lines", "40"]).catch(() => null);
        if (a.address in this.snips) { this.snips[a.address] = snippet(r?.stdout); cx.notify(); }
      });
    }
  }

  card(t, id, tint, title, side, body, action) {
    return v_flex().id(id).px(10).py(8).gap(4).rounded(8).border_1().border_color(t.border).bg(t.raised).cursor_pointer()
      .hover(s => s.border_color(tint)).on_click(action)
      .child(h_flex().gap(8).items_center()
        .child(div().size(8).flex_none().rounded(4).bg(tint))
        .child(div().flex_1().min_w(0).truncate().font_medium().child(title))
        .child(div().flex_none().text_size(11).text_color(t.dim).child(side)))
      .when(Boolean(body), el => el.child(div().text_size(12).text_color(t.muted).child(body)));
  }

  section(t, title, cards) {
    return cards.length ? [div().pt(6).text_size(11).font_semibold().text_color(t.muted).child(`${title} · ${cards.length}`), ...cards] : [];
  }

  render(cx) {
    const t = theme();
    const all = agents(), blocked = all.filter(a => a.status === "blocked"), done = all.filter(a => a.status === "done");
    this.read(cx, blocked);
    const name = a => (a.title ?? "").replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}]+/u, "").trim() || a.program?.name || "agent";
    const where = a => `${a.space_name} · ${a.tab_name}`;
    const failing = (shared("inbox.github")?.prs ?? []).filter(pr => pr.ci === "fail");
    const sl = this.digest?.slack, order = i => (i.urgent ? 0 : i.kind === "ask" ? 1 : 2);
    const asks = (sl?.items ?? []).filter(i => !i.ticked).sort((a, b) => order(a) - order(b) || b.at - a.at);
    const count = blocked.length + done.length + failing.length + this.reviews.length + asks.filter(i => i.kind === "ask").length;
    if (count !== (shared("inbox.count") ?? 0)) setShared("inbox.count", count);
    const cards = [
      ...this.section(t, "Needs you", blocked.map(a => this.card(t, `in-b-${a.address}`, t.blocked, name(a), where(a), this.snips[a.address] || null,
        () => run("agent.focus", { terminal: a.address })))),
      ...this.section(t, "Finished", done.map(a => this.card(t, `in-d-${a.address}`, t.done, name(a), where(a), null,
        () => run("agent.focus", { terminal: a.address })))),
      ...this.section(t, "Slack", asks.map(item => this.slack(t, item))),
      ...this.section(t, "CI failed", failing.map(pr => this.card(t, `in-c-${pr.number}-${pr.branch}`, t.ansi1, `#${pr.number} ${pr.title}`, pr.branch,
        pr.failed.map(c => c.name).join(" · "), (_e, cx) => cx.open_url(pr.failed.find(c => c.url)?.url ?? pr.url)))),
      ...this.section(t, "Review requested", this.reviews.map(pr => this.card(t, `in-r-${pr.url}`, t.accent, `#${pr.number} ${pr.title}`, ago(Date.parse(pr.updatedAt)),
        pr.repository?.nameWithOwner ?? null, (_e, cx) => cx.open_url(pr.url)))),
    ];
    return v_flex().id("inbox").size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background).border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(svg("mods/inbox/inbox.svg").size(14).text_color(t.muted))
        .child(div().font_semibold().child("Inbox"))
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(this.error ?? this.digestError ?? (sl && !sl.connected ? "Slack connector is not signed in" : sl?.error) ?? ""))
        .when(Boolean(WORK_DIGEST), el => el.child(div().id("in-sweep").flex_none().px(6).h(22).flex().items_center().rounded(5).text_size(11).text_color(t.dim).cursor_pointer()
          .hover(s => s.bg(t.hover).text_color(t.foreground)).on_click((_e, cx) => this.ask(cx, "/slack/sweep"))
          .child(sl?.running ? "sweeping…" : sl?.lastAt ? `Slack ${ago(sl.lastAt)}` : "Slack")))
        .child(div().id("in-reload").flex_none().px(6).h(22).flex().items_center().rounded(5).text_size(11).text_color(t.dim).cursor_pointer()
          .hover(s => s.bg(t.hover).text_color(t.foreground)).on_click((_e, cx) => this.tick(cx, true))
          .child(this.busy ? "checking…" : this.pulledAt ? `GitHub ${ago(this.pulledAt)}` : "GitHub")))
      .child(cards.length
        ? v_flex().id("in-body").flex_1().min_h(0).overflow_y_scrollbar().px(12).pb(12).pt(6).gap(6).children(cards)
        : div().flex_1().p(16).text_color(t.dim).child("Nothing needs you"))
      .when(Boolean(this.digest), el => el.child(this.standup(t, this.digest.standup)));
  }
}
