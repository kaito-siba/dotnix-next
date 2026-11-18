// Inbox の中身を取りに行く側。2 つの mod が読み込む (../../_show.nix が両方へ写す)
//   inbox      開いている間だけ生きるモーダル (./main.js)。操作した時に取り直す
//   show-tabs  いつも出ているタブバー。数分おきに見に行き、件数をボタンに出す
// 取った物は shared に置き、モーダルと tasks mod が読む
//   "inbox.github"   { prs, at }      開いている pane の branch の pull request と CI
//   "inbox.digest"   { state, error } 常駐機の work-digest の状態: Slack の依頼と standup の下書き (modules/work-digest)
import { svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, agents, exec, run, shared, setShared } from "herdr";
// work-digest の API の URL。使わない machine では null (nix が書く: ../../_show.nix)
import { WORK_DIGEST } from "./env.js";

const TICK = 60000, PULLS = 3 * 60000, MAX_REPOS = 12;
// sweep や下書きが走っている間は、終わるのを早めに見に行く
const DIGEST = 60000, DIGEST_BUSY = 10000;
const FAILED = new Set(["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"]);
const TRUNK = new Set(["main", "master", "develop", "trunk"]);

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

let busy = false, pulledAt = 0;
let asking = false, digestAt = 0;

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

// work-digest に聞く。path が無ければ状態を読むだけ。状態を変える call は、変えた後の状態か、始めた事だけを返す
export function ask(cx, path, body) {
  if (!WORK_DIGEST || asking && !path) return;
  asking = true;
  cx.spawn(async cx => {
    // 聞けなかった時は、前の状態を残して error だけを付ける
    let state = shared("inbox.digest")?.state ?? null, error = null;
    try {
      if (path) {
        const r = await fetch(`${WORK_DIGEST}${path}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body ?? {}) });
        if (!r.ok) throw new Error((await r.json().catch(() => null))?.error ?? `work-digest answered ${r.status}`);
      }
      const r = await fetch(`${WORK_DIGEST}/state`);
      if (!r.ok) throw new Error((await r.json().catch(() => null))?.error ?? `work-digest answered ${r.status}`);
      state = await r.json();
    } catch (e) { error = String(e?.message ?? e); }
    finally {
      asking = false; digestAt = Date.now();
      if (!same({ state, error }, shared("inbox.digest"))) setShared("inbox.digest", { state, error });
      cx.notify();
    }
  });
}

// 数分おきに見に行き始める。いつも出ている mod の init から 1 度だけ呼ぶ
export function start(cx) {
  cx.timer.every(TICK, cx => refresh(cx));
  refresh(cx);
  if (!WORK_DIGEST) return;
  cx.timer.every(DIGEST_BUSY, cx => {
    const d = shared("inbox.digest")?.state;
    if (d?.slack.running || d?.standup.running || Date.now() - digestAt >= DIGEST) ask(cx);
  });
  ask(cx);
}

// 自分の手を待っている物。agent の状態は app の live data から、他は shared から
export function waiting() {
  const all = agents(), order = i => (i.urgent ? 0 : i.kind === "ask" ? 1 : 2);
  return {
    blocked: all.filter(a => a.status === "blocked"),
    done: all.filter(a => a.status === "done"),
    slack: (shared("inbox.digest")?.state?.slack.items ?? []).filter(i => !i.ticked).sort((a, b) => order(a) - order(b) || b.at - a.at),
    failing: (shared("inbox.github")?.prs ?? []).filter(pr => pr.ci === "fail"),
  };
}

// Slack の FYI は数えない。commitment と review 依頼は、Inbox を開いた時に aw-secretary から読むので数えない
export function count(w = waiting()) {
  return w.blocked.length + w.done.length + w.failing.length + w.slack.filter(i => i.kind === "ask").length;
}

// タブバーに出すボタン。押すとモーダルを開き、もう一度押すと閉じる。見た目は隣の panel のボタンに合わせる
export function button(t) {
  const n = count();
  return h_flex().id("inbox-open").h(26).px(8).gap(5).flex_none().items_center().rounded(6).text_size(12).bg(t.chrome).text_color(t.muted)
    .hover(s => s.bg(t.hover)).on_mouse_down("left", (_e, cx) => cx.stop_propagation())
    .on_click(() => run("mod.open", { name: "inbox" }))
    .child(svg("mods/inbox/inbox.svg").size(14)).child(n ? `Inbox ${n}` : "Inbox");
}
