// 下端の status bar に出す、Claude Code と Codex の利用上限の bar。同梱の workspace-status に ../../_app-home.nix が差し込む
//   Claude Code  statusLine に挟んだ herdr-usage-statusline (../../usage/claude-statusline.sh) が書く file。host の分と、sbx の sandbox の中の分がある
//   Codex        herdr-usage-codex (../../usage/codex.py) が codex app-server に訊いた答え
// どれも {at, windows: [{mins, used, resets_at}]} の形で、at と resets_at は unix 秒
import { div } from "gpui-kit";
import { h_flex } from "gpui-base";
import { exec, readTextFile, checking, settings } from "herdr";
// 読む file と herdr-usage-codex の path。nix が書く
import { CLAUDE, CODEX } from "./env.js";

const READ = 30000, ASK = 5 * 60000;
// これより古い記録は薄く出す
const STALE = 30 * 60000;
// これより古い記録は捨てる。1 週間の枠についても、もう何も言えない
const FORGET = 7 * 86400000;
// 終わる時刻がこれだけしか違わなければ、同じ枠とみなす
const SAME = 60000;
// 1 つの file から読む字数と枠の数の上限
const MAX_TEXT = 4096, MAX_WINDOWS = 4;
const BAR = 44, FAINT = 0.5;
// 幅の見積もりに使う 1 字の幅 (px)。text_size(11.8) の欧文と和文
const NARROW = 6.6, WIDE = 11.8;
// 左に並ぶ字の外の幅。px と icon と、workspace-status が元から並べる物の間の gap の分
const CHROME = 142;

const num = v => typeof v === "number" && Number.isFinite(v) ? v : null;

// sandbox の中の file は、乗っ取られた sandbox が何を書いていてもおかしくない。数だけを拾い、範囲に収める
export function parse(text, now) {
  if (typeof text !== "string" || text.length > MAX_TEXT) return [];
  let data;
  try { data = JSON.parse(text); } catch { return []; }
  const at = num(data?.at);
  if (at === null || !Array.isArray(data.windows)) return [];
  const seen = Math.min(at * 1000, now);
  if (now - seen > FORGET) return [];
  const found = [];
  for (const w of data.windows.slice(0, MAX_WINDOWS)) {
    const mins = num(w?.mins), used = num(w?.used), reset = num(w?.resets_at);
    if (!Number.isInteger(mins) || mins < 1 || mins > 31 * 1440 || used === null || reset === null) continue;
    // 枠は、今から枠の長さより先には終わらない
    if (reset * 1000 > now + mins * 60000 + SAME || found.some(f => f.mins === mins)) continue;
    found.push({ mins, used: Math.min(100, Math.max(0, used)), reset: reset * 1000, at: seen });
  }
  return found;
}

// 長さごとに枠を 1 つ選ぶ。終わる時刻が遅い方が新しい枠で、同じ枠なら使った量は減らないので多い方を取る
// 止まっている session の statusLine が古い値を後から書いても、host と sandbox の両方で使っていても、bar は戻らない
export function merge(now, ...lists) {
  const best = new Map();
  for (const w of lists.flat()) {
    if (now - w.at > FORGET) continue;
    const b = best.get(w.mins);
    if (!b || w.reset > b.reset + SAME) best.set(w.mins, w);
    else if (w.reset >= b.reset - SAME) best.set(w.mins, { mins: w.mins, used: Math.max(b.used, w.used), reset: Math.max(b.reset, w.reset), at: Math.max(b.at, w.at) });
  }
  return [...best.values()].sort((a, b) => a.mins - b.mins);
}

// 300 → "5h"、10080 → "7d"
const span = mins => mins % 1440 === 0 ? `${mins / 1440}d` : mins % 60 === 0 ? `${mins / 60}h` : `${mins}m`;

// 枠が戻るまでの時間を "3d4h"、"2h13m"、"45m" の形で返す
export function left(ms) {
  const m = Math.max(1, Math.ceil(ms / 60000)), d = Math.floor(m / 1440), h = Math.floor(m % 1440 / 60);
  return d ? `${d}d${h}h` : h ? `${h}h${m % 60}m` : `${m}m`;
}

const width = s => [...s].reduce((n, ch) => n + (ch.codePointAt(0) < 0x2e80 ? NARROW : WIDE), 0);

// 1 つの枠の、出す字と色。終わった枠は今どれだけ使ったか分からないので、空の bar にして % を出さない
export function gauge(t, w, now) {
  const passed = w.reset <= now, used = passed ? 0 : w.used;
  return {
    span: span(w.mins),
    used,
    pct: passed ? null : `${Math.round(used)}%`,
    left: passed ? null : left(w.reset - now),
    fill: used >= 95 ? t.blocked : used >= 80 ? t.working : t.accent,
    faint: passed || now - w.at > STALE,
  };
}

export class Limits {
  constructor(cx) {
    this.claude = []; this.codex = [];
    this.reading = new Set(); this.asking = false;
    this.room = Infinity;
    if (checking()) return;
    cx.timer.every(READ, cx => this.read(cx));
    this.read(cx);
    if (CODEX) {
      cx.timer.every(ASK, cx => this.ask(cx));
      this.ask(cx);
    }
  }

  // 読み終わる前に次を始めない。sandbox が file を FIFO にすると、読みが返らない
  read(cx) {
    for (const path of CLAUDE) {
      if (this.reading.has(path)) continue;
      this.reading.add(path);
      cx.spawn(async cx => {
        try {
          // this.claude は await の後で読む。前に読むと、同時に読んだもう 1 つの file の分を消す
          const text = await readTextFile(path), now = Date.now();
          this.claude = merge(now, this.claude, parse(text, now));
        } catch {}
        finally { this.reading.delete(path); cx.notify(); }
      });
    }
  }

  ask(cx) {
    if (this.asking) return;
    this.asking = true;
    cx.spawn(async cx => {
      try {
        const r = await exec(CODEX, [], { timeout: 30000 }), now = Date.now();
        if (r.code === 0) this.codex = merge(now, this.codex, parse(r.stdout.trim(), now));
      } catch {}
      finally { this.asking = false; cx.notify(); }
    });
  }

  // 根の大きさは zoom を掛けた後で届くが、mod の中の長さには zoom がもう一度掛かるので割り戻す
  resize(size, cx) {
    this.room = size.width / (Number(settings()?.zoom) || 1);
    cx.notify();
  }

  // 出す物が無い時に親の gap を増やさないよう、0 個か 1 個の要素の配列を返す
  // others は同じ bar の左に並ぶ字。それと合わせて収まらない時は、戻るまでの時間、%、全体の順に落とす
  view(t, others) {
    const now = Date.now();
    const groups = [["Claude", this.claude], ["Codex", this.codex]]
      .filter(([, list]) => list.length)
      .map(([name, list]) => ({ name, gauges: list.map(w => gauge(t, w, now)) }));
    if (!groups.length) return [];
    const taken = CHROME + others.reduce((n, s) => n + width(s || ""), 0);
    const need = detail => groups.reduce((n, g) => n + 16 + width(g.name) + g.gauges.reduce((m, x) => m + 10 + width(x.span) + 5 + BAR
      + (detail >= 2 && x.pct ? 5 + width(x.pct) : 0) + (detail >= 3 && x.left ? 5 + width(x.left) : 0), 0), 0);
    const detail = [3, 2, 1].find(d => taken + need(d) <= this.room);
    if (!detail) return [];
    return [h_flex().flex_none().gap(16).items_center().children(groups.map(g => this.group(t, g, detail)))];
  }

  group(t, g, detail) {
    return h_flex().flex_none().gap(10).items_center()
      .child(div().when(g.gauges.every(x => x.faint), el => el.opacity(FAINT)).child(g.name))
      .children(g.gauges.map(x => h_flex().flex_none().gap(5).items_center().when(x.faint, el => el.opacity(FAINT))
        .child(div().text_color(t.dim).child(x.span))
        .child(div().flex_none().w(BAR).h(5).rounded_full().bg(t.border)
          .when(x.used > 0, el => el.child(div().h_full().w(Math.max(5, BAR * x.used / 100)).rounded_full().bg(x.fill))))
        .when(detail >= 2 && Boolean(x.pct), el => el.child(x.pct))
        .when(detail >= 3 && Boolean(x.left), el => el.child(div().text_color(t.dim).child(x.left)))));
  }
}
