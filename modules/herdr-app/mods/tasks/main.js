// 表示している space の tab ごとに、そこの agent が何をしているかを出す右 panel
// goal、plan、判断と仮定、残っている事は、task-notes が turn の後に書く要約から (../task-notes)。変更と commit は、agent が今居る folder の git から出す
// 要約は agent の動く machine の $XDG_STATE_HOME/task-notes/<tab の id>.json にある
import { View, div, svg, image } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { spaces, panes, agents, shared, theme, run, exec, layout } from "herdr";
import { where } from "./where.js";

const POLL = 15000;
const STEP = { done: ["✓", "done"], now: ["◐", "working"], todo: ["○", "dim"] };
const KIND = { decision: ["DECISION", "accent"], assumption: ["ASSUMPTION", "working"], you_said: ["YOU SAID", "done"] };
const READ = 'cat "${XDG_STATE_HOME:-$HOME/.local/state}/task-notes/$1.json" 2>/dev/null';
// 変更を数える元: remote の既定の branch から分かれた所。無ければ local の main か master、それも無ければ commit していない分だけ
const CHANGES = `
base=HEAD
for ref in origin/HEAD origin/main origin/master main master; do
  if b=$(git merge-base HEAD "$ref" 2>/dev/null) && [ -n "$b" ]; then base=$b; break; fi
done
git rev-list --count "$base..HEAD" 2>/dev/null || echo 0
git diff --numstat "$base" 2>/dev/null
# git がまだ追っていない新しいファイルも数える。全ての行が追加に当たる
git ls-files --others --exclude-standard -z 2>/dev/null | xargs -0 wc -l 2>/dev/null | grep -v ' total$' | awk '{ n=$1; $1=""; sub(/^ /, ""); print n "\\t0\\t" $0 }'
`;

// agent が title の前に付ける状態の印 ("✳ ", "⠋ - ") を落とす
const clean = s => (s ?? "").replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}]+/u, "").trim();

// navigator と同じ呼び方: agent は自分で付けた title (Claude Code なら session の名前) で、他は動いている program の名前で呼ぶ
function label(p) {
  const told = p.program?.agent ? clean(p.title) : "";
  return told || p.program?.name || p.title || "shell";
}

function ago(ms) {
  const m = Math.floor((Date.now() - ms) / 60000);
  return m < 1 ? "just now" : m < 60 ? `${m}m ago` : m < 1440 ? `${Math.floor(m / 60)}h ago` : `${Math.floor(m / 1440)}d ago`;
}

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) { const found = find(child, id); if (found) return found; }
  return null;
}

export default class Tasks extends View {
  init(_props, cx) {
    // places は tab ごとに where で訊いた、agent の居る folder と branch
    this.summaries = {}; this.changes = {}; this.places = {}; this.busy = {}; this.selected = null;
    // 隠れている間も timer は回るので、見えている時だけ取り直す
    cx.timer.every(POLL, cx => { if (this.visible()) this.load(cx, true); });
  }

  visible() {
    const root = layout(), panel = find(root, "panel"), body = find(root, "panel-body");
    return Boolean(panel) && !panel.hidden && body?.active === "tasks";
  }

  // 表示している space の tab。端末を持たない tab (mod だけの tab) は出さない
  tasks() {
    const space = spaces().find(s => s.active);
    if (!space) return { space: null, list: [] };
    const all = panes(), list = [];
    for (const tab of space.tabs) {
      const mine = all.filter(p => p.tab === tab.id && p.terminal && p.cwd);
      // agent の居る pane を優先する
      const pane = mine.find(p => p.program?.agent) ?? mine[0];
      if (!pane) continue;
      // 他の machine の id には "<machine>/" が前に付く。その machine の上では付かない
      const key = space.machine ? tab.id.slice(space.machine.length + 1) : tab.id;
      list.push({ id: tab.id, key, tab, name: label(pane), program: pane.program, cwd: pane.cwd, branch: pane.branch, terminal: pane.terminal, on: space.machine, agent: agents().find(a => a.tab === tab.id) });
    }
    return { space, list };
  }

  load(cx, again) {
    const task = this.current;
    if (!task || this.busy[task.id] || (!again && task.id in this.summaries)) return;
    this.busy[task.id] = true;
    cx.spawn(async cx => {
      try {
        const [note, place] = await Promise.all([
          exec("sh", ["-c", READ, "read", task.key], { on: task.on }).catch(() => null),
          where(task),
        ]);
        this.places[task.id] = place;
        // agent が下の階層に居ても、数えるのは checkout 全体
        const diff = await exec("sh", ["-c", CHANGES], { cwd: place.root ?? place.cwd, on: task.on }).catch(() => null);
        let summary = null;
        try { summary = note?.stdout ? JSON.parse(note.stdout) : null; } catch {}
        this.summaries[task.id] = summary;
        const [commits, ...lines] = (diff?.stdout ?? "").split("\n").filter(Boolean);
        this.changes[task.id] = {
          commits: Number(commits) || 0,
          files: lines.map(line => { const [add, del, ...path] = line.split("\t"); return { path: path.join("\t"), add, del }; }).filter(f => f.path),
        };
      } finally { this.busy[task.id] = false; cx.notify(); }
    });
  }

  render(cx) {
    const t = theme();
    const { space, list } = this.tasks();
    if (!list.some(x => x.id === this.selected)) this.selected = (list.find(x => x.tab.active) ?? list[0])?.id ?? null;
    const task = list.find(x => x.id === this.selected) ?? null;
    this.current = task;
    if (this.visible()) this.load(cx, false);
    const s = task ? this.summaries[task.id] : null, changes = task ? this.changes[task.id] : null;
    const branch = task ? (this.places[task.id] ?? task).branch : null;
    const pr = branch ? (shared("inbox.github")?.prs ?? []).find(p => p.branch === branch) : null;

    const label = (text, right) => h_flex().gap(8).items_center().pb(2)
      .child(div().text_size(11).font_medium().text_color(t.dim).child(text))
      .when(Boolean(right), el => el.child(div().flex_1()).child(right));
    const dot = status => status === "working" ? div().size(9).flex_none().rounded(5).border_2().border_color(t.working)
      : div().size(8).flex_none().rounded(4).bg(status ? t[status] : t.dim);
    const pic = prog => !prog?.icon ? null : prog.tint ? svg(prog.icon).size(14).flex_none().text_color(t.muted) : image(prog.icon).w(14).h(14).flex_none();
    // 幅が狭いので、navigator の行から cwd を除いた形にする。branch は選んだ task の見出しの下に出ている
    const row = x => h_flex().id(`tk-${x.id}`).px(8).py(6).gap(8).items_center().rounded(6).text_size(12.5).cursor_pointer()
      .when(x.id === this.selected, el => el.bg(t.selected)).hover(st => st.bg(t.hover))
      .on_click((_e, cx) => { this.selected = x.id; this.current = x; this.load(cx, true); cx.notify(); })
      .child(dot(x.tab.status))
      .when(Boolean(pic(x.program)), el => el.child(pic(x.program)))
      .child(div().flex_1().min_w(0).truncate().child(x.name))
      .child(div().flex_none().max_w(140).truncate().text_size(11).text_color(t.dim).child(x.tab.name));

    const body = !task ? [div().text_color(t.dim).child(space ? "No terminals in this space" : "No space")] : [
      v_flex().gap(3)
        .child(div().text_size(15).font_semibold().child(task.name))
        .child(div().text_size(11).text_color(t.dim).child([`${space.name} › ${task.tab.name}`, branch, s?.updatedAt ? `updated ${ago(s.updatedAt)}` : ""].filter(Boolean).join(" · "))),
      ...(task.agent?.status === "blocked" ? [h_flex().id("tk-open").p(10).gap(8).items_center().rounded(8).bg(t.raised).border_1().border_color(t.blocked).cursor_pointer()
        .on_click(() => run("agent.focus", { terminal: task.agent.address }))
        .child(div().flex_1().text_size(11).font_semibold().text_color(t.blocked).child("WAITING ON YOU"))
        .child(div().text_size(11).text_color(t.dim).child("open →"))] : []),
      ...(!s ? [div().text_size(12.5).text_color(t.dim).child(task.id in this.summaries
        ? "No summary yet. It appears after the agent's next turn that changes a file."
        : "Loading…")] : [
        v_flex().gap(4).child(label("GOAL")).child(div().text_size(12.5).child(s.goal)),
        ...(s.steps?.length ? [v_flex().gap(3)
          .child(label("PLAN", s.planFile ? div().max_w(200).truncate().text_size(11).text_color(t.accent).child(s.planFile.split("/").pop()) : null))
          .children(s.steps.map(st => h_flex().gap(8).items_start().text_size(12.5)
            .child(div().w(14).flex_none().text_color(t[STEP[st.state]?.[1] ?? "dim"]).child(STEP[st.state]?.[0] ?? "○"))
            .child(div().flex_1().min_w(0).text_color(st.state === "done" ? t.muted : t.foreground).child(st.text))))] : []),
        ...(s.decisions?.length ? [v_flex().gap(5).child(label("DECISIONS AND ASSUMPTIONS"))
          .children(s.decisions.map(d => h_flex().gap(8).items_start().text_size(12.5)
            .child(div().flex_none().mt(1).px(5).py(1).rounded(4).bg(t.raised).text_size(9.5).font_semibold().text_color(t[KIND[d.kind]?.[1] ?? "muted"]).child(KIND[d.kind]?.[0] ?? d.kind))
            .child(div().flex_1().min_w(0).child(d.text))))] : []),
      ]),
      v_flex().gap(3)
        .child(label("CHANGES", div().text_size(11).text_color(t.dim).child([
          changes?.commits ? `${changes.commits} commit${changes.commits === 1 ? "" : "s"}` : "",
          pr ? `PR #${pr.number} ${pr.ci === "fail" ? "✗" : pr.ci === "pass" ? "✓" : pr.ci === "pending" ? "⋯" : ""}` : "",
        ].filter(Boolean).join(" · "))))
        .children((changes?.files ?? []).slice(0, 12).map(f => h_flex().gap(10).text_size(11.5)
          .child(div().flex_1().min_w(0).truncate().child(f.path))
          .child(div().flex_none().text_color(t.done).child(f.add === "-" || f.add === "0" ? "" : `+${f.add}`))
          .child(div().flex_none().text_color(t.blocked).child(f.del === "-" || f.del === "0" ? "" : `−${f.del}`))))
        .when((changes?.files.length ?? 0) > 12, el => el.child(div().text_size(11).text_color(t.dim).child(`and ${changes.files.length - 12} more`)))
        .when(Boolean(changes) && !changes.files.length, el => el.child(div().text_size(12).text_color(t.dim).child("No changes against the base branch"))),
      ...(s?.notDone?.length ? [v_flex().gap(3).child(label("NOT DONE OR RISKY"))
        .children(s.notDone.map(text => h_flex().gap(8).items_start().text_size(12.5)
          .child(div().flex_none().text_color(t.working).child("!")).child(div().flex_1().min_w(0).child(text))))] : []),
    ];

    return v_flex().id("tasks").size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background).border_1().border_color(t.border).text_color(t.foreground).text_size(13)
      .child(h_flex().h(42).flex_none().px(14).gap(8).items_center().border_b(1).border_color(t.border)
        .child(svg("mods/tasks/tasks.svg").size(14).text_color(t.muted))
        .child(div().font_semibold().child("Tasks"))
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(space?.name ?? ""))
        .when(Boolean(s), el => el.child(div().flex_none().text_size(11).text_color(t.dim).child(`${s.turns} turn${s.turns === 1 ? "" : "s"}`))))
      .when(list.length > 1, el => el.child(v_flex().flex_none().p(6).gap(1).border_b(1).border_color(t.border).children(list.map(row))))
      .child(v_flex().id("tasks-body").flex_1().min_h(0).overflow_y_scrollbar().px(14).py(12).gap(14).children(body))
      .when(Boolean(task), el => el.child(h_flex().flex_none().px(14).py(9).gap(8).items_center().border_t(1).border_color(t.border).bg(t.chrome)
        .child(div().flex_1())
        .child(div().id("tk-diff").flex_none().px(10).py(4).rounded(5).text_size(11.5).font_medium().bg(t.solid).text_color(t.solid_foreground).cursor_pointer()
          .hover(st => st.opacity(0.85))
          .on_click(() => { run("tab.select", { id: task.id }); run("layout.select", { stack: "panel-body", child: "changes" }); })
          .child("Review diff"))));
  }
}
