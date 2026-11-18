// 左バーの Agents の一覧。同梱の agents mod (./upstream.js、build の時に原本を写す) を継承し、広い時の見た目だけを描き直す
// 細い rail、並び順のメニュー、pin、sub-agent の木、状態が変わった時刻の記録は、同梱の物をそのまま使う
// 上に状態ごとの数、その下に agent ごとの 2 段の行、1 日以上待機のままの agent は SLEEPING の下に 1 行ずつ並べ、下にチェキに入れた絵を置く
import { div, image, svg, PathBuilder } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { agents, terminals, panes, focused, spaces, run, theme, setAgentOrder, openOverlay, props, settings } from "herdr";
import Agents, { narrow, title, leadPanes, kidStatus, RANK, sortOf } from "./upstream.js";
import { readAsks, askOf, clip } from "./asks.js";
// チェキの傾きと、下の縁に書く字の svg (./memo/) の置き方。どちらも build の時に ./memo.py が書く
import { TILT, MEMO } from "./memo.js";
// 色と字と状態の印は Tasks (../tasks) と分け合う
import { ROUND, palette, WORD, tone, clock, initials, mark } from "./lycoreco.js";

const HERE = "mods/cheki-agents";
// これだけ待機のままの agent は SLEEPING に入れる (ms)
const SLEEP = 24 * 3600000;
const GAUGE = [["blocked", "CALL"], ["working", "RUN"], ["done", "DONE"], ["idle", "STBY"]];

// 絵は repo に入れず、app home の backgrounds/sidebar.png に置く。無ければチェキは空の写真になる
const PHOTO = "backgrounds/sidebar.png";
// 絵の縦横比 (幅 1066 : 高さ 1736)。絵を差し替えたら、ここと CROP も合わせる
const RATIO = 1736 / 1066;
// チェキに切り出す所。絵の幅と高さに対する割合で、左上の角と幅
const CROP = { left: 0.02, top: 0.08, width: 0.61 };
// 枠の上と下の幅。上と横は、写真の角がはみ出さない幅まで太くする (cheki())
const TOP = 9, BOTTOM = 30;

// 題名の頭に space の名前が付いていれば落とす ("knowledge-portal #5826 …" → "#5826 …")。語の途中で切れる時と、落とすと空になる時は落とさない
function bare(name, space) {
  if (!space || name.slice(0, space.length).toLowerCase() !== space.toLowerCase()) return name;
  const rest = name.slice(space.length);
  if (/^[\p{L}\p{N}]/u.test(rest)) return name;
  return rest.replace(/^[\s:·|/\-–—]+/u, "") || name;
}

// チェキの形。w と h は一覧の根の大きさ (zoom を割り戻した長さ)。狭すぎて置けない時は null
// gpui では要素を回せないので、写真は真っ直ぐ置き、傾けた窓の外を傾けた枠で覆う。窓を覆う真っ直ぐな矩形の角が、枠の外へはみ出ないように横の幅を決める
function cheki(w, h) {
  const rad = TILT * Math.PI / 180, cos = Math.cos(rad), sin = Math.sin(rad);
  // 窓を覆う真っ直ぐな矩形は、横へ窓の高さ × k、縦へ窓の幅 × k だけ窓からはみ出す。横と上の枠は、それより 2 太くする
  const k = Math.abs(Math.sin(2 * rad)) / 2;
  const frame = (ww, wh) => ({ s: Math.max(9, Math.ceil(wh * k) + 2), top: Math.max(TOP, Math.ceil(ww * k) + 2) });
  // 窓は 3:4。カードは根の幅から決め、高さが根の 45% を超える時は縮める
  let ww = w - 62, wh = ww * 4 / 3, { s, top } = frame(ww, wh);
  ww = w - 44 - 2 * s; wh = ww * 4 / 3;
  ({ s, top } = frame(ww, wh));
  if (wh + top + BOTTOM > h * 0.45) {
    wh = h * 0.45 - top - BOTTOM; ww = wh * 3 / 4;
    ({ s, top } = frame(ww, wh));
  }
  if (ww < 60) return null;
  const cw = ww + 2 * s, ch = wh + top + BOTTOM;
  const turn = ([x, y]) => [x * cos - y * sin, x * sin + y * cos];
  const box = (l, t, r, b) => [[l, t], [r, t], [r, b], [l, b]];
  const wl = -cw / 2 + s, wr = cw / 2 - s, wt = -ch / 2 + top, wb = ch / 2 - BOTTOM;
  // テープはカードの上の縁に、カードよりさらに 5 度回して貼る
  const tape = box(-27, -8.5, 27, 8.5).map(([x, y]) => {
    const a = 5 * Math.PI / 180;
    return turn([x * Math.cos(a) - y * Math.sin(a), x * Math.sin(a) + y * Math.cos(a) - ch / 2 - 0.5]);
  });
  const shapes = {
    shadows: [box(-cw / 2 - 2, -ch / 2 + 3, cw / 2 + 2, ch / 2 + 7), box(-cw / 2, -ch / 2 + 2, cw / 2, ch / 2 + 4)].map(p => p.map(turn)),
    outer: box(-cw / 2, -ch / 2, cw / 2, ch / 2).map(turn),
    // 窓は逆回りに辿る。塗りの決まりが even-odd でも non-zero でも穴になる
    hole: box(wl, wt, wr, wb).reverse().map(turn),
    tape,
  };
  const glass = box(wl, wt, wr, wb).map(turn);
  // 下の縁の字の baseline。縁の真ん中より、字の高さの半分ほど下
  const memo = [turn([wl + 2, wb + BOTTOM / 2 + 4]), turn([wr - 2, wb + BOTTOM / 2 + 4])];
  // カードの中心を原点にした座標を、全てを囲む箱の左上を原点にした座標へ移す
  const every = [...shapes.shadows.flat(), ...shapes.outer, ...tape];
  const x0 = Math.min(...every.map(p => p[0])) - 2, y0 = Math.min(...every.map(p => p[1])) - 2;
  const x1 = Math.max(...every.map(p => p[0])) + 2, y1 = Math.max(...every.map(p => p[1])) + 2;
  const at = ([x, y]) => [x - x0, y - y0];
  const px = glass.map(p => p[0]), py = glass.map(p => p[1]);
  return {
    width: x1 - x0, height: y1 - y0,
    shadows: shapes.shadows.map(p => p.map(at)), outer: shapes.outer.map(at), hole: shapes.hole.map(at), tape: shapes.tape.map(at),
    photo: { left: Math.min(...px) - x0, top: Math.min(...py) - y0, width: Math.max(...px) - Math.min(...px), height: Math.max(...py) - Math.min(...py) },
    memo: memo.map(at),
  };
}

function chekiView(g, c, rootWidth) {
  // 多角形は箱に対する割合で描く。px で渡すと zoom の掛かり方を気にする事になる
  const pct = ([x, y]) => [`${(x / g.width * 100).toFixed(3)}%`, `${(y / g.height * 100).toFixed(3)}%`];
  const fill = (polygons, color) => window.paint_path(polygons.reduce((b, p) => b.add_polygon(p.map(pct), true), PathBuilder.fill()).build(), color).absolute().top(0).left(0).size_full();
  const iw = g.photo.width / CROP.width, ih = iw * RATIO;
  const d = new Date();
  // 字は ./memo.py が枠と同じだけ傾けた svg。[左, 上, 幅, 高さ] は baseline の点からの位置
  const memo = (name, [x, y], color) => {
    const [l, t, w, h] = MEMO[name];
    return svg(`${HERE}/memo/${name}.svg`).absolute().left(x + l).top(y + t).w(w).h(h).text_color(color);
  };
  return div().absolute().bottom(16).left((rootWidth - g.width) / 2).w(g.width).h(g.height)
    .children(g.shadows.map(p => fill([p], c.shadow)))
    .child(div().absolute().left(g.photo.left).top(g.photo.top).w(g.photo.width).h(g.photo.height).overflow_hidden().bg(c.photoBg).opacity(c.photo)
      .child(image(PHOTO).absolute().left(-CROP.left * iw).top(-CROP.top * ih).w(iw).h(ih)))
    .child(fill([g.outer, g.hole], c.frame))
    .child(fill([g.tape], c.tape))
    .child(memo("LycoReco", g.memo[0], c.ink))
    .child(memo(`date-${d.getMonth() + 1}-${d.getDate()}`, g.memo[1], c.date));
}

export default class ChekiAgents extends Agents {
  render(cx) {
    if (props()?.sortMenu) return super.render(cx);
    // 細い rail は同梱の物のまま。質問の抜粋は Inbox と分け合うので、畳んでいる間も読む
    if (narrow()) {
      readAsks(cx, agents());
      return super.render(cx);
    }
    const t = theme(), c = palette(t);
    const sort = sortOf(), byPriority = sort.id === "priority";
    let list = agents();
    this.listed = new Map(list.map(a => [a.address, a.status]));
    const all = terminals();
    this.migratePins(all);
    const shown = focused()?.agent;
    const now = Date.now();
    this.track(list, now);
    readAsks(cx, list);

    // 木の中に出る sub-agent は、pin されていない限り自分の行を持たない (同梱の物と同じ)
    const nested = new Set(list.flatMap(a => this.tree(all, a.address).map(s => s.t.address)));
    list = list.filter(a => a.pinned || !nested.has(a.address));
    const urgency = new Map(list.map(a => [a.address, Math.max(this.rank(a), ...this.tree(all, a.address).map(s => RANK[kidStatus(s.t, this.listed)] ?? 0))]));
    if (byPriority) list = [...list].sort((x, y) => urgency.get(y.address) - urgency.get(x.address) || this.since(y) - this.since(x) || y.seq - x.seq);
    const asleep = a => a.status === "idle" && !a.focused && !a.pinned && urgency.get(a.address) <= RANK.idle && now - this.since(a) >= SLEEP;
    const pinned = list.filter(a => a.pinned);
    const awake = list.filter(a => !a.pinned && !asleep(a));
    const sleeping = list.filter(a => !a.pinned && asleep(a));
    setAgentOrder([...pinned, ...awake, ...sleeping].map(a => a.address));

    // 行の名前は同梱の物と同じ決め方 (名前の付いた tab か、agent が付けた題名)。自動の tab の番号なら program の名前にし、頭の space の名前は落とす
    const tabCounts = new Map();
    for (const a of list) tabCounts.set(a.tab, (tabCounts.get(a.tab) ?? 0) + 1);
    const leads = leadPanes(panes());
    const spaceList = spaces();
    const tabs = new Map(spaceList.flatMap(s => s.tabs).map(tab => [tab.id, tab]));
    const name = a => {
      const tab = tabs.get(a.tab), many = tabCounts.get(a.tab) > 1;
      const label = tab ? title(many ? { ...tab, named: false } : tab, many ? a : leads.get(a.tab)) : (a.title || a.program?.name || "");
      return bare(/^\d+$/.test(label) ? a.program?.name || label : label, a.space_name);
    };
    // 符丁: space の頭文字と、その space の中で何番目の tab か (tab.select の番号と同じ)
    const code = a => {
      const space = spaceList.find(s => s.id === a.space);
      const n = space ? space.tabs.findIndex(tab => tab.id === a.tab) + 1 : 0;
      return `${initials(a.space_name)}-${n || "?"}`;
    };

    const counts = {};
    for (const a of list) counts[a.status] = (counts[a.status] ?? 0) + 1;

    const rows = [];
    const awakeRows = a => {
      const subs = this.tree(all, a.address);
      rows.push(this.row(t, c, a, name(a), code(a), subs, now));
      if (!this.folded.has(a.address)) rows.push(...subs.map(s => this.subRow(t, s, shown, byPriority)));
    };
    pinned.forEach(awakeRows);
    // space ごとに並べる時は、space の名前で区切る。agents() の中で同じ space の agent は隣り合う
    let space = null;
    for (const a of awake) {
      if (!byPriority && a.space !== space) rows.push(this.divider(t, c, a.space_name || "", false));
      space = a.space;
      awakeRows(a);
    }
    if (sleeping.length) {
      rows.push(this.divider(t, c, "SLEEPING", true));
      rows.push(...sleeping.map(a => this.sleeper(t, a, name(a), now)));
    }

    // 根の大きさは zoom を掛けた後で届くが、mod の中の長さには zoom がもう一度掛かるので割り戻す
    const zoom = Number(settings()?.zoom) || 1;
    const area = this.area ? { w: this.area.width / zoom, h: this.area.height / zoom } : null;
    const g = area && cheki(area.w, area.h);

    return v_flex()
      .id("cheki-agents")
      .size_full()
      .min_h(0)
      .relative()
      .overflow_hidden()
      .bg(t.chrome)
      .border_t(1)
      .border_color(t.border)
      .text_size(13)
      .on_size_change((size, cx) => { this.area = size; cx.notify(); })
      .child(svg(`${HERE}/dots.svg`).absolute().top(0).left(0).w(640).h(2400).text_color(c.dots))
      .when(Boolean(g), el => el.child(chekiView(g, c, area.w)))
      .child(this.header(t, c, sort))
      .child(this.gauge(c, counts))
      .when(list.length === 0, el => el.child(div().px(14).pt(12).text_size(12).text_color(t.dim).child("No agent status yet. Agents show up here when they report their status. Older versions and agents inside tmux may not.")))
      .child(v_flex().id("ag-list").flex_1().min_h(0).px(8).pt(12).gap(3).overflow_y_scrollbar().mode("always").children(rows));
  }

  header(t, c, sort) {
    return h_flex().flex_none().pl(14).pr(12).pt(14).pb(9).items_center().justify_between()
      .child(div().font_family(ROUND).text_size(11).font_weight(800).text_color(c.accent).child("AGENTS"))
      .child(div()
        .id("ag-sort")
        .text_color(t.dim)
        .hover(s => s.text_color(t.foreground))
        .on_click(() => openOverlay({ mod: "agents", kind: "popup", width: 200, height: 140, props: { sortMenu: true } }))
        .tooltip(`Sort agents: ${sort.label}`)
        .child(svg(`mods/workspace-chrome/${sort.icon}.svg`).size(14)));
  }

  // 状態ごとの数。0 の所は薄くする
  gauge(c, counts) {
    return h_flex().flex_none().mx(10).gap(5).children(GAUGE.map(([st, label]) => {
      const [ink, bg] = tone(c, st), n = counts[st] ?? 0;
      return v_flex().flex_1().items_center().pt(5).pb(4).rounded(11).bg(bg).text_color(ink).font_family(ROUND)
        .when(n === 0, el => el.opacity(0.38))
        .child(div().text_size(19).font_weight(800).line_height("21px").child(String(n)))
        .child(div().text_size(8.5).font_weight(700).child(label));
    }));
  }

  // 上に題名と経過、下に符丁と状態。呼んでいる agent は、その下に質問の抜粋 (./asks.js)
  row(t, c, a, name, code, subs, now) {
    const [ink] = tone(c, a.status);
    const when = this.since(a);
    const ask = a.status === "blocked" ? askOf(a) : null;
    const hovered = this.hovered === a.address;
    // 他の machine の agent (`vps/t7`) は、どの machine かを添える
    const machine = a.address.includes("/") ? a.address.split("/")[0] : null;
    const open = !this.folded.has(a.address);
    return v_flex()
      .id(`ag-${a.address}`)
      .flex_none()
      .px(8)
      .pt(6)
      .pb(7)
      .gap(4)
      .rounded(12)
      .border(1.5)
      .border_color(a.focused ? c.accent : `${c.accent}00`)
      .when(a.status === "blocked", el => el.bg(c.callBg))
      .when(a.focused && a.status !== "blocked", el => el.bg(c.onBg))
      .cursor_pointer()
      .hover(s => s.bg(t.hover))
      .on_hover((on, cx) => {
        if (on) this.hovered = a.address;
        else if (this.hovered === a.address) this.hovered = null;
        cx.notify();
      })
      .on_click(() => run("pane.focus", { pane: a.pane }))
      .child(h_flex().items_center().gap(8)
        .child(div().flex_1().min_w(0).truncate().text_size(12.5).font_weight(600).text_color(t.foreground).child(name))
        .when(hovered, el => el.child(this.pin(t, a)))
        .when(!hovered && Boolean(when), el => el.child(div().flex_none().font_family(ROUND).text_size(10).font_weight(700).text_color(t.dim).child(clock(now - when)))))
      .child(h_flex().items_center().gap(7)
        .when(a.pinned, el => el.child(svg("mods/workspace-chrome/pin.svg").size(10).flex_none().text_color(t.dim)))
        .child(div().flex_none().px(6).rounded(7).bg(c.accentBg).text_color(c.accent).font_family(ROUND).text_size(9.5).font_weight(700).line_height("15px").child(code))
        .child(h_flex().flex_none().items_center().gap(4).font_family(ROUND).text_size(9.5).font_weight(800).text_color(ink).child(mark(a.status, ink)).child(WORD[a.status] ?? a.status.toUpperCase()))
        .when(Boolean(machine), el => el.child(div().text_size(9.5).text_color(t.dim).child(machine)))
        .when(subs.length > 0, el => el.child(div().flex_1()).child(div()
          .id(`fold-${a.address}`)
          .flex_none()
          .h(16)
          .px(3)
          .gap(3)
          .flex()
          .items_center()
          .rounded(4)
          .text_size(10)
          .text_color(t.dim)
          .cursor_pointer()
          .hover(s => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => {
            cx.stop_propagation();
            open ? this.folded.add(a.address) : this.folded.delete(a.address);
            cx.notify();
          })
          .child(svg(`mods/workspace-chrome/chevron-${open ? "down" : "right"}.svg`).size(11).flex_none())
          .when(!open, el => el.child(String(subs.length))))))
      .when(Boolean(ask), el => el.child(div().max_h(30).overflow_hidden().text_size(11).line_height("15px").text_color(t.muted).child(clip(ask))));
  }

  // hover した行の、経過の代わりに出す pin のボタン (同梱の物と同じ)
  pin(t, a) {
    return div()
      .id(`pin-${a.address}`)
      .flex_none()
      .p(2)
      .rounded(4)
      .text_color(t.dim)
      .cursor_pointer()
      .hover(s => s.bg(t.hover).text_color(t.foreground))
      .tooltip(a.pinned ? "Unpin" : "Pin to the top")
      .on_click((_e, cx) => {
        cx.stop_propagation();
        run("terminal.pin", { terminal: a.address, pinned: !a.pinned });
        // 行が pointer の下から動き、hover が外れた知らせは来ない
        this.hovered = null;
        cx.notify();
      })
      .child(svg(`mods/workspace-chrome/${a.pinned ? "pin-off" : "pin"}.svg`).size(12));
  }

  // 1 日以上待機のままの agent。題名と経過だけの 1 行
  sleeper(t, a, name, now) {
    return h_flex()
      .id(`ag-${a.address}`)
      .flex_none()
      .h(22)
      .px(8)
      .gap(8)
      .items_center()
      .rounded(8)
      .cursor_pointer()
      .hover(s => s.bg(t.hover))
      .on_click(() => run("pane.focus", { pane: a.pane }))
      .child(div().flex_1().min_w(0).truncate().text_size(11.5).text_color(t.dim).child(name))
      .when(Boolean(this.since(a)), el => el.child(div().flex_none().font_family(ROUND).text_size(10).font_weight(700).text_color(t.dim).child(clock(now - this.since(a)))));
  }

  // 区切り。SLEEPING と、space ごとに並べる時の space の名前
  divider(t, c, label, zzz) {
    return h_flex().flex_none().mx(8).mt(10).mb(3).gap(6).items_center()
      .when(zzz, el => el.child(svg(`${HERE}/zzz.svg`).size(12).flex_none().text_color(c.idle)))
      .child(div().flex_none().font_family(ROUND).text_size(9.5).font_weight(700).text_color(t.dim).child(label))
      .child(div().flex_1().border_t(1.5).border_dashed().border_color(t.border));
  }
}
