// Inbox の中身を取りに行く側。2 つの mod が読み込む (../../_show.nix が両方へ写す)
//   inbox      開いている間だけ生きるモーダル (./main.js)。操作した時に取り直す
//   show-tabs  いつも出ているタブバー。数分おきに見に行き、件数をボタンに出す
// 取った物は shared に置き、モーダルと tasks mod が読む
//   "inbox.github"   { prs, at }      開いている pane の branch の pull request と CI
//   "inbox.reviews"  { list, error }  自分宛の review 依頼
//   "inbox.digest"   { state, error } 常駐機の work-digest の状態: Slack の依頼と standup の下書き (modules/work-digest)
//   "inbox.commitments"  { view, error }  常駐機の aw-secretary の commitment (自分への約束) のうち、手を付けるべき物 (GET /commitments?view=inbox の答え)
import { svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, agents, exec, run, shared, setShared } from "herdr";
// work-digest と aw-secretary の API の URL。使わない machine では null (nix が書く: ../../_show.nix)
import { WORK_DIGEST, COMMITMENTS } from "./env.js";

const TICK = 60000, PULLS = 3 * 60000, REVIEWS = 5 * 60000, MAX_REPOS = 12;
// sweep や下書きが走っている間は、終わるのを早めに見に行く
const DIGEST = 60000, DIGEST_BUSY = 10000;
// commitment は日に 1 度の collect で増えるので間を空ける。collect の最中は、終わるのを早めに見に行く
const SECRETARY = 5 * 60000, SECRETARY_BUSY = 10000;
// 書き込みの答えをこれだけ待っても届かなければ、次の書き込みを受ける (ms)。書いた Inbox が閉じると、その答えは届かない
const WRITING = 30000;
const FAILED = new Set(["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"]);
const TRUNK = new Set(["main", "master", "develop", "trunk"]);

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

let busy = false, pulledAt = 0, reviewedAt = 0;
let asking = false, digestAt = 0;
let reading = false, consultedAt = 0, sentAt = 0;

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

async function requests() {
  let list = shared("inbox.reviews")?.list ?? [], error = null;
  try {
    const r = await exec("gh", ["search", "prs", "--review-requested=@me", "--state=open", "--limit", "20", "--json", "number,title,url,repository,updatedAt"]);
    if (r.code !== 0) throw new Error(r.stderr.trim().split("\n")[0] || "gh failed");
    list = JSON.parse(r.stdout);
  } catch (e) { error = String(e?.message ?? e); }
  if (!same({ list, error }, shared("inbox.reviews"))) setShared("inbox.reviews", { list, error });
}

// GitHub を見に行く。now が無ければ、前に見てから間が空いた物だけ
export function refresh(cx, now) {
  if (busy) return;
  const pull = now || Date.now() - pulledAt >= PULLS, review = now || Date.now() - reviewedAt >= REVIEWS;
  if (!pull && !review) return;
  busy = true;
  cx.spawn(async cx => {
    try {
      if (pull) { await pulls(); pulledAt = Date.now(); }
      if (review) { await requests(); reviewedAt = Date.now(); }
    } finally { busy = false; cx.notify(); }
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

// aw-secretary の答え。URL の無い machine では、前に置かれた物 (shared は app を閉じても残る) があっても読まない
export const secretary = () => COMMITMENTS ? shared("inbox.commitments") ?? null : null;

// 答えを待っている書き込みがあるか。続けて押した時に server で後の物が先に適用されないよう、答えが届くまで次の書き込みは受けない
export const writing = () => Date.now() - sentAt < WRITING;

// view の新しさは (rev, at) で比べる。rev は DB に書くたびに増え、日付が変わる時と collect が始まる時は rev が同じまま中身が変わる
const newer = (a, b) => !b || a.rev > b.rev || a.rev === b.rev && a.at >= b.at;

// aw-secretary に聞く。id が無ければ inbox の view を読むだけ。id があれば body で commitment を変え、変えた後の view を受け取る
export function consult(cx, id, body) {
  if (!COMMITMENTS || id && writing()) return;
  const mine = Date.now(), knew = secretary()?.view?.running ?? false;
  if (id) sentAt = mine;
  else reading = true;
  cx.spawn(async cx => {
    let view = null, error = null, running = false;
    try {
      const r = await (id
        ? fetch(`${COMMITMENTS}/commitments/${id}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) })
        : fetch(`${COMMITMENTS}/commitments?view=inbox`));
      if (r.ok) view = await r.json();
      else {
        const e = await r.json().catch(() => null);
        running = e?.running ?? false;
        throw new Error(e?.error ?? `aw-secretary answered ${r.status}`);
      }
    } catch (e) { error = String(e?.message ?? e); }
    finally {
      consultedAt = Date.now();
      // WRITING を過ぎて次を送った後に届いた答えでは、次の書き込みを待つのをやめない
      if (id && sentAt === mine) sentAt = 0;
      else if (!id) reading = false;
      // 答えが届く順は聞いた順と限らないので、古い view は置かない。collect の最中と知る前に始めた読みの答えでは、running を外さない。collect が始まる前に読んだ view かもしれない
      const now = secretary(), last = now?.view ?? null;
      if (!view || newer(view, last) && (knew || view.running || !last?.running)) {
        // 聞けなかった時と書けなかった時は、前の view を残して error だけを付ける。collect の最中の 503 は running: true が付くので、すぐに key を止める
        const next = { view: view ?? (running && last ? { ...last, running } : last), error };
        if (!same(next, now)) setShared("inbox.commitments", next);
      }
      cx.notify();
    }
  });
}

// 数分おきに見に行き始める。いつも出ている mod の init から 1 度だけ呼ぶ
export function start(cx) {
  cx.timer.every(TICK, cx => refresh(cx));
  refresh(cx);
  if (COMMITMENTS) {
    cx.timer.every(SECRETARY_BUSY, cx => {
      if (!reading && (secretary()?.view?.running || Date.now() - consultedAt >= SECRETARY)) consult(cx);
    });
    consult(cx);
  }
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
    reviews: shared("inbox.reviews")?.list ?? [],
    commitments: secretary()?.view?.items ?? [],
  };
}

// Slack の FYI と、期限が近いだけ・済んだかもしれないだけの commitment は数えない
export function count(w = waiting()) {
  return w.blocked.length + w.done.length + w.failing.length + w.reviews.length + w.slack.filter(i => i.kind === "ask").length
    + w.commitments.filter(c => c.reason === "triage" || c.reason === "overdue").length;
}

// タブバーに出すボタン。押すとモーダルを開き、もう一度押すと閉じる。見た目は隣の panel のボタンに合わせる
export function button(t) {
  const n = count();
  return h_flex().id("inbox-open").h(26).px(8).gap(5).flex_none().items_center().rounded(6).text_size(12).bg(t.chrome).text_color(t.muted)
    .hover(s => s.bg(t.hover)).on_mouse_down("left", (_e, cx) => cx.stop_propagation())
    .on_click(() => run("mod.open", { name: "inbox" }))
    .child(svg("mods/inbox/inbox.svg").size(14)).child(n ? `Inbox ${n}` : "Inbox");
}
