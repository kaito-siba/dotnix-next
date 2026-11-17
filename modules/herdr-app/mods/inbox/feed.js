// Inbox の中身を取りに行く側。2 つの mod が読み込む (../../_show.nix が両方へ写す)
//   inbox      開いている間だけ生きるモーダル (./main.js)。操作した時に取り直す
//   show-tabs  いつも出ているタブバー。数分おきに見に行き、件数をボタンに出す
// 取った物は shared に置き、モーダルと tasks mod が読む
//   "inbox.github"   { prs, at }      開いている pane の branch の pull request と CI
//   "inbox.reviews"  { list, error }  自分宛の review 依頼
//   "inbox.digest"   { state, error } 常駐機の work-digest の状態: Slack の依頼と standup の下書き (modules/work-digest)
//   "inbox.commitments"  { view, error, wrote, sentAt }  常駐機の aw-secretary の commitment (自分への約束) のうち、手を付けるべき物 (GET /commitments?view=inbox の答え)
//                        wrote は送った書き込みの数。sentAt は答えを待っている書き込みを送った時刻 (ms) で、待っていなければ null
import { svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, agents, exec, run, shared, setShared } from "herdr";
// work-digest と aw-secretary の API の URL。使わない machine では null (nix が書く: ../../_show.nix)
import { WORK_DIGEST, COMMITMENTS } from "./env.js";

const TICK = 60000, PULLS = 3 * 60000, REVIEWS = 5 * 60000, MAX_REPOS = 12;
// sweep や下書きが走っている間は、終わるのを早めに見に行く
const DIGEST = 60000, DIGEST_BUSY = 10000;
// commitment は日に 1 度の collect で増えるので間を空ける。collect の最中と、書き込みを送った後は早めに見に行く
const SECRETARY = 5 * 60000, SECRETARY_BUSY = 10000;
// 書き込みの答えをこれだけ待っても置かれなければ、書いた mod が閉じて途切れたとみなす (ms)
const WRITING = 30000;
const FAILED = new Set(["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"]);
const TRUNK = new Set(["main", "master", "develop", "trunk"]);

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

let busy = false, pulledAt = 0, reviewedAt = 0;
let asking = false, digestAt = 0;
// readSeen は、最後に view を置いた読みを始めた時の wrote
let reading = false, readSeen = 0, consultedAt = 0;

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

// 答えを待っている書き込みがあるか。書き込みは、server での順を送った順に揃えるため、1 度に 1 つだけ送る
export function writing(s) {
  const age = Date.now() - (s?.sentAt ?? -Infinity);
  return age >= 0 && age < WRITING;
}

const failure = async r => (await r.json().catch(() => null))?.error ?? `aw-secretary answered ${r.status}`;

// aw-secretary に聞く。id が無ければ inbox の view を読むだけ。id があれば body で commitment を変え、変えた後の view を受け取る
// 読みの答えは、書き込みを待っていない時に始めて、その後に書き込みが送られていない時だけ置く。他は書く前の view かもしれない。捨てた分は、タブバーが読み直して埋める
export function consult(cx, id, body) {
  const before = secretary();
  if (!COMMITMENTS || id && writing(before)) return;
  // 書き込みには mod をまたいで順を付けるので、数と送った時刻を shared に置く
  const mine = (before?.wrote ?? 0) + (id ? 1 : 0), clean = !writing(before);
  if (id) setShared("inbox.commitments", { view: before?.view ?? null, error: before?.error ?? null, wrote: mine, sentAt: Date.now() });
  else reading = true;
  cx.spawn(async cx => {
    let view = null, error = null;
    try {
      const r = await (id
        ? fetch(`${COMMITMENTS}/commitments/${id}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) })
        : fetch(`${COMMITMENTS}/commitments?view=inbox`));
      if (!r.ok) throw new Error(await failure(r));
      view = await r.json();
    } catch (e) { error = String(e?.message ?? e); }
    finally {
      consultedAt = Date.now();
      if (!id) reading = false;
      const now = secretary();
      if ((now?.wrote ?? 0) === mine && (id || clean)) {
        if (!id && view) readSeen = mine;
        // 聞けなかった時と書けなかった時 (collect の最中の 503 等) は、前の view を残して error だけを付ける
        const next = { ...now, view: view ?? now?.view ?? null, error };
        if (id) next.sentAt = null;
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
    // 書き込みの後は、view を読めるまで読み直す。書いた mod (Inbox) が答えを置かずに閉じた時や、読みの答えを捨てた時の分も、ここで埋める
    readSeen = secretary()?.wrote ?? 0;
    cx.timer.every(SECRETARY_BUSY, cx => {
      const s = secretary();
      if (!reading && !writing(s) && (s?.view?.running || (s?.wrote ?? 0) !== readSeen || Date.now() - consultedAt >= SECRETARY)) consult(cx);
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
