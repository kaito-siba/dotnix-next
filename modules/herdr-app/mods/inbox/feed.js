// Inbox の中身を取りに行く側。2 つの mod が読み込む (../../_app-home.nix が両方へ写す)
//   inbox      開いている間だけ生きるモーダル (./main.js)。操作した時に取り直す
//   panel-tabs いつも出ているタブバー。数分おきに見に行き、件数をボタンに出す
// 取った物は shared に置き、モーダルと tasks mod が読む
//   "inbox.github"   { prs, at }      開いている pane の branch の pull request と CI
import { svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, agents, exec, run, shared, setShared } from "herdr";

const TICK = 60000, PULLS = 3 * 60000, MAX_REPOS = 12;
const FAILED = new Set(["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"]);
const TRUNK = new Set(["main", "master", "develop", "trunk"]);

let busy = false, pulledAt = 0;

// GitHub を見に行っている最中か
export const checking = () => busy;

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

// 開いている pane の branch ごとに、その pull request と CI を見る。main 等の幹の branch は見ない
async function pulls() {
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
  setShared("inbox.github", { prs, at: Date.now() });
}

// GitHub を見に行く。now が無ければ、前に見てから間が空いた時だけ
export function refresh(cx, now) {
  if (busy || !now && Date.now() - pulledAt < PULLS) return;
  busy = true;
  cx.spawn(async cx => {
    try { await pulls(); pulledAt = Date.now(); }
    finally { busy = false; cx.notify(); }
  });
}

// 数分おきに見に行き始める。いつも出ている mod の init から 1 度だけ呼ぶ
export function start(cx) {
  cx.timer.every(TICK, cx => refresh(cx));
  refresh(cx);
}

// 自分の手を待っている物。agent の状態は app の live data から、CI は shared から
export function waiting() {
  const all = agents();
  return {
    blocked: all.filter(a => a.status === "blocked"),
    done: all.filter(a => a.status === "done"),
    failing: (shared("inbox.github")?.prs ?? []).filter(pr => pr.ci === "fail"),
  };
}

// Slack と commitment は、Inbox を開いた時に aw-secretary から読むので数えない
export function count(w = waiting()) {
  return w.blocked.length + w.done.length + w.failing.length;
}

// タブバーに出すボタン。押すとモーダルを開き、もう一度押すと閉じる。見た目は隣の panel のボタンに合わせる
export function button(t) {
  const n = count();
  return h_flex().id("inbox-open").h(26).px(8).gap(5).flex_none().items_center().rounded(6).text_size(12).bg(t.chrome).text_color(t.muted)
    .hover(s => s.bg(t.hover)).on_mouse_down("left", (_e, cx) => cx.stop_propagation())
    .on_click(() => run("mod.open", { name: "inbox" }))
    .child(svg("mods/inbox/inbox.svg").size(14)).child(n ? `Inbox ${n}` : "Inbox");
}
