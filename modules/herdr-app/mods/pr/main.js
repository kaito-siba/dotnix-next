// focus している pane の branch の pull request を、CI と review の状態と一緒に見る
// dialog を閉じると mod も止まるので、取り直すのも CI の終了を知らせるのも開いている間だけ
import { View, div } from "gpui-kit";
import { v_flex, h_flex, TextView, Scrollbar, v_virtual_list, VirtualListScrollHandle } from "gpui-base";
import { spaces, panes, focused, exec, run, notify, theme, props, closeOverlay } from "herdr";

const ROW = 28, TICK = 15000;
const LABEL = { fail: "failed", running: "running", pass: "passed", skip: "skipped" };

// 同じ branch から出した pull request が複数あり得る (閉じて出し直した時など)。open の物を優先し、無ければ最後に動いた物を出す
const QUERY = `
query($owner: String!, $name: String!, $branch: String!) {
  repository(owner: $owner, name: $name) {
    open: pullRequests(headRefName: $branch, states: [OPEN], first: 1) { nodes { ...pr } }
    last: pullRequests(headRefName: $branch, first: 1, orderBy: { field: UPDATED_AT, direction: DESC }) { nodes { ...pr } }
  }
}
fragment pr on PullRequest {
  number title url body state isDraft baseRefName headRefName mergeable reviewDecision
  latestReviews(first: 30) { nodes { author { login } state url } }
  reviewRequests(first: 30) { nodes { requestedReviewer { ... on User { login } ... on Bot { login } ... on Mannequin { login } ... on Team { name } } } }
  reviewThreads(first: 100) { nodes { isResolved isOutdated path line comments(first: 20) { nodes { author { login } body url } } } }
  commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 100) { nodes {
    __typename
    ... on CheckRun { name status conclusion detailsUrl checkSuite { workflowRun { workflow { name } } } }
    ... on StatusContext { context state targetUrl }
  } } } } } }
}
`;

function location() {
  const space = spaces().find(s => s.active), f = focused();
  const pane = f?.pane ? panes().find(p => p.pane === f.pane) : null;
  return { cwd: pane?.cwd || f?.cwd || space?.folder, on: space?.machine ?? null, branch: pane?.branch ?? space?.branch ?? null };
}

const words = s => s.toLowerCase().replace(/_/g, " ");
// pull request の template 等に入っている HTML の comment は、GitHub の画面と同じく出さない
const prose = s => s.replace(/<!--[\s\S]*?-->/g, "").trim();

// GitHub Actions 等の check run と、外部の CI が付ける commit status の 2 種類がある
function checkState(c) {
  if (c.__typename === "StatusContext") return c.state === "SUCCESS" ? "pass" : c.state === "PENDING" || c.state === "EXPECTED" ? "running" : "fail";
  if (c.status !== "COMPLETED") return "running";
  return c.conclusion === "SUCCESS" ? "pass" : c.conclusion === "NEUTRAL" || c.conclusion === "SKIPPED" ? "skip" : "fail";
}

// 一覧の行。head が見出しで、他は選べる行。state は印の色、text は右に出す markdown
function rows(pr) {
  const order = Object.keys(LABEL);
  const checks = (pr.commits.nodes[0]?.commit.statusCheckRollup?.contexts.nodes ?? []).map(c => {
    const flow = c.checkSuite?.workflowRun?.workflow.name;
    const name = c.__typename === "StatusContext" ? c.context : flow ? `${flow} / ${c.name}` : c.name;
    const state = checkState(c), note = words(c.conclusion ?? c.status ?? c.state), url = c.detailsUrl ?? c.targetUrl ?? pr.url;
    return { key: `check:${name}`, kind: "check", state, main: name, side: note, url, text: `**${name}**\n\n${note}` };
  }).sort((a, b) => order.indexOf(a.state) - order.indexOf(b.state) || a.main.localeCompare(b.main));
  const reviews = [
    ...pr.latestReviews.nodes.map(r => {
      const who = r.author?.login ?? "ghost", note = words(r.state);
      return { key: `review:${who}`, kind: "review", state: r.state === "APPROVED" ? "pass" : r.state === "CHANGES_REQUESTED" ? "fail" : "skip", main: who, side: note, url: r.url, text: `**${who}** ${note}` };
    }),
    // 見えない team への依頼は相手が null で返る
    ...pr.reviewRequests.nodes.map(r => r.requestedReviewer).filter(Boolean).map(r => {
      const who = r.login ?? r.name;
      return { key: `request:${who}`, kind: "review", state: "running", main: who, side: "requested", url: pr.url, text: `**${who}** review requested` };
    }),
  ];
  const threads = pr.reviewThreads.nodes.filter(t => !t.isResolved && t.comments.nodes.length).map(t => {
    const first = t.comments.nodes[0], where = `${t.path}${t.line ? `:${t.line}` : ""}`;
    const talk = t.comments.nodes.map(c => `**${c.author?.login ?? "ghost"}**\n\n${prose(c.body)}`).join("\n\n---\n\n");
    // 一覧は幅が狭いので、ファイル名と行だけを出す。path は右に出す
    return { key: `thread:${first.url}`, kind: "thread", state: t.isOutdated ? "skip" : "running", main: where.split("/").pop(), side: first.author?.login ?? "ghost", url: first.url,
      text: `\`${where}\`${t.isOutdated ? " (outdated)" : ""}\n\n${talk}` };
  }).sort((a, b) => order.indexOf(a.state) - order.indexOf(b.state));
  const section = (title, items) => items.length ? [{ key: `head:${title}`, head: `${title} · ${items.length}` }, ...items] : [];
  const all = [
    { key: "pr", kind: "pr", main: "Description", side: "", url: pr.url, text: prose(pr.body) || "*No description*" },
    ...section("Checks", checks), ...section("Reviews", reviews), ...section("Unresolved threads", threads),
  ];
  // 同じ名前の check が並ぶ事がある (matrix や再実行)。行の key は重ねられない
  const seen = new Set();
  for (const row of all) { while (seen.has(row.key)) row.key += "'"; seen.add(row.key); }
  return all;
}

export default class PullRequest extends View {
  init(_props, cx) {
    this.loc = location();
    // pr の undefined は取っている途中、null は pull request が無い印
    this.pr = undefined; this.rows = []; this.sel = "pr"; this.error = null; this.busy = false;
    this.running = 0; this.ticks = 0;
    this.scroll = VirtualListScrollHandle.new();
    this.handle = cx.focus_handle();
    this.handle.focus();
    // 開いた直後の focus は dialog の表示に奪われる事があるので、もう一度取る
    cx.timer.after(600, () => this.handle.focus());
    // CI が動いている間は TICK ごと、それ以外は 4 回に 1 回 (1 分ごと) 取り直す
    cx.timer.every(TICK, cx => { if (this.running || ++this.ticks % 4 === 0) this.refresh(cx); });
    this.refresh(cx);
  }

  // {owner} {repo} {branch} は gh が cwd の repository から埋める。埋めるのは -F の値だけ
  refresh(cx) {
    const { cwd, on } = this.loc;
    if (!cwd || this.busy) return;
    this.busy = true;
    cx.spawn(async cx => {
      try {
        const r = await exec("gh", ["api", "graphql", "-F", "owner={owner}", "-F", "name={repo}", "-F", "branch={branch}", "-f", `query=${QUERY}`], { cwd, on });
        if (r.code !== 0) throw new Error(r.stderr.trim().split("\n")[0] || "gh failed");
        const repo = JSON.parse(r.stdout).data?.repository;
        if (!repo) throw new Error("Repository not found on GitHub");
        this.show(repo.open.nodes[0] ?? repo.last.nodes[0] ?? null);
        this.error = null;
      } catch (e) { this.error = String(e?.message ?? e); }
      finally { this.busy = false; cx.notify(); }
    });
  }

  show(pr) {
    const was = this.running;
    this.pr = pr; this.rows = pr ? rows(pr) : [];
    const checks = this.rows.filter(r => r.kind === "check");
    this.running = checks.filter(c => c.state === "running").length;
    if (pr && was && !this.running) {
      const failed = checks.some(c => c.state === "fail");
      notify({ title: failed ? "CI failed" : "CI passed", body: `#${pr.number} ${pr.title}`, level: failed ? "error" : "success" });
    }
    if (!this.rows.some(r => r.key === this.sel)) this.sel = "pr";
  }

  select(key, cx) {
    this.sel = key;
    const at = this.rows.findIndex(r => r.key === key);
    if (at >= 0) this.scroll.scroll_to_item(at, "center");
    cx.notify();
  }

  move(step, cx) {
    const list = this.rows.filter(r => !r.head);
    if (!list.length) return;
    const at = list.findIndex(r => r.key === this.sel);
    this.select(list[Math.min(list.length - 1, Math.max(0, at + step))].key, cx);
  }

  // URL を focus している端末の prompt に貼って閉じる。改行は送らないので、続けて指示を書ける
  // 貼るのは clipboard 越し (terminal.paste) なので、clipboard は URL で上書きされる
  paste(url, cx) {
    const f = focused(), pane = f?.pane ? panes().find(p => p.pane === f.pane) : null;
    if (!pane?.terminal) { notify({ title: "Pull request", body: "Focus a terminal pane first, then paste again", level: "warning" }); return; }
    cx.write_to_clipboard(`${url} `);
    run("terminal.paste");
    closeOverlay(props().overlay);
    run("pane.focus", { pane: pane.pane });
  }

  key(e, cx) {
    if (e.modifiers.control || e.modifiers.alt || e.modifiers.platform) return;
    const url = this.rows.find(r => r.key === this.sel)?.url;
    if (e.key === "escape" || e.key === "q") closeOverlay(props().overlay);
    else if (e.key === "j" || e.key === "down") this.move(1, cx);
    else if (e.key === "k" || e.key === "up") this.move(-1, cx);
    else if (e.key === "g") this.move(e.modifiers.shift ? Infinity : -Infinity, cx);
    else if ((e.key === "enter" || e.key === "o") && url) cx.open_url(url);
    else if (e.key === "y" && url) { cx.write_to_clipboard(url); this.copied = url; cx.notify(); }
    else if (e.key === "p" && url) this.paste(url, cx);
    else if (e.key === "r") this.refresh(cx);
    else return;
    cx.stop_propagation();
  }

  empty() {
    if (!this.loc.cwd) return "No folder";
    if (this.error) return this.error;
    if (this.pr === undefined) return "Loading…";
    return `No pull request for ${this.loc.branch ?? "this branch"}`;
  }

  // virtual list の renderer の中では on_click 等の handler を登録できない。click は list 側の on_item_click で受ける
  row(row, t, color) {
    if (row.head) return h_flex().h(ROW).px(8).items_center().text_size(11).font_semibold().text_color(t.muted).child(row.head);
    return h_flex().h(ROW).px(8).gap(8).items_center().rounded(7).cursor_pointer()
      .when(this.sel === row.key, el => el.bg(t.selected)).hover(s => s.bg(t.hover))
      .when(row.kind !== "pr", el => el.child(div().size(8).flex_none().rounded(4).bg(color[row.state])))
      .child(div().flex_1().min_w(0).truncate().child(row.main))
      .child(div().flex_none().text_size(11).text_color(t.dim).child(row.side));
  }

  list(t, color) {
    const rows = this.rows;
    return div().w(380).h_full().flex_none().relative().border_r(1).border_color(t.border)
      .child(v_virtual_list("pr-list", rows.length, ROW, i => rows[i].key,
        range => rows.slice(range.start, range.end).map(row => this.row(row, t, color)))
        .track_scroll(this.scroll).size_full().px(6)
        .on_item_click((key, cx) => {
          if (key.startsWith("head:")) return;
          this.select(key, cx); this.handle.focus();
        }))
      .child(Scrollbar.vertical("pr-list").absolute().inset_0());
  }

  detail(t) {
    const row = this.rows.find(r => r.key === this.sel) ?? this.rows[0];
    return v_flex().flex_1().min_w(0).min_h(0)
      .child(h_flex().h(34).flex_none().px(14).items_center().border_b(1).border_color(t.border).text_size(11).text_color(t.dim)
        .child(div().id("pr-url").flex_1().min_w(0).truncate().cursor_pointer().hover(s => s.text_color(t.foreground))
          .on_click((_e, cx) => cx.open_url(row.url))
          .child(this.copied === row.url ? "Copied URL" : row.url)))
      // 行ごとに id を変えて、前の行の scroll 位置を持ち越さない
      .child(v_flex().id(`pr-detail-${row.key}`).flex_1().min_h(0).overflow_y_scrollbar().px(20).py(14).text_size(13)
        .child(TextView.markdown(`pr-md-${row.key}`, row.text).selectable(true)));
  }

  summary(pr, t, color) {
    const [state, tint] = pr.state === "MERGED" ? ["Merged", t.ansi5] : pr.state === "CLOSED" ? ["Closed", t.ansi1] : pr.isDraft ? ["Draft", t.muted] : ["Open", t.ansi2];
    const count = (kind, state) => this.rows.filter(r => r.kind === kind && (!state || r.state === state)).length;
    const facts = [
      [`${pr.baseRefName} ← ${pr.headRefName}`, t.muted],
      pr.mergeable === "CONFLICTING" && ["conflicts", color.fail],
      pr.reviewDecision && [words(pr.reviewDecision), pr.reviewDecision === "APPROVED" ? color.pass : pr.reviewDecision === "CHANGES_REQUESTED" ? color.fail : t.muted],
      ...["fail", "running", "pass"].map(s => count("check", s) > 0 && [`${count("check", s)} ${LABEL[s]}`, color[s]]),
      count("thread") > 0 && [`${count("thread")} unresolved`, color.running],
    ].filter(Boolean);
    return v_flex().flex_none().px(14).py(10).gap(6).border_b(1).border_color(t.border)
      .child(h_flex().gap(8).items_center()
        .child(div().flex_none().px(6).rounded(4).border_1().border_color(tint).text_size(11).text_color(tint).child(state))
        .child(div().flex_none().text_color(t.dim).child(`#${pr.number}`))
        .child(div().min_w(0).truncate().font_semibold().child(pr.title)))
      .child(h_flex().gap(12).text_size(12).children(facts.map(([text, tint]) => div().flex_none().text_color(tint).child(text))));
  }

  render() {
    const t = theme(), pr = this.pr;
    const color = { fail: t.ansi1, running: t.ansi3, pass: t.ansi2, skip: t.dim };
    // dialog の枠は角丸だが、中身は角丸に切り抜かれない。背景も同じ丸みにして、角からはみ出させない
    return v_flex().id("pr").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .size_full().min_h(0).rounded(10).bg(t.popover).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(10).items_center().border_b(1).border_color(t.border)
        .child(div().font_semibold().child("Pull request"))
        .child(div().min_w(0).truncate().text_size(12).text_color(t.dim).child(pr && this.error ? this.error : this.loc.cwd?.split("/").pop() ?? ""))
        .child(div().flex_1())
        .child(div().flex_none().text_size(11).text_color(t.dim).child("j/k move · Enter open · y copy URL · p paste to prompt · r reload · q close")))
      .child(pr
        ? v_flex().flex_1().min_h(0)
          .child(this.summary(pr, t, color))
          .child(h_flex().flex_1().min_h(0).items_start().child(this.list(t, color)).child(this.detail(t).h_full()))
        : div().p(16).text_color(t.dim).child(this.empty()));
  }
}
