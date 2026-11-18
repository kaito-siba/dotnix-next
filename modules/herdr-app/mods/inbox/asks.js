// 返事を待っている agent の画面の最後を読んで、質問の抜粋を shared の "inbox.asks" に { [address]: { seq, text, at } } で置く
// text が null の間は、at (ms) に読み始めて、まだ読み終えていない。どちらの mod が読んでいるかは問わない
// 2 つの mod が読み込む (../../_show.nix が両方へ写す)
//   backdrop-agents  いつも出ている左バーの Agents の一覧。止まった agent をすぐ読みに行き、行の下に抜粋を出す
//   inbox            開いている間だけ生きるモーダル (./main.js)。置かれた抜粋を使い、無い時だけ自分で読みに行く
import { div } from "gpui-kit";
import { v_flex } from "gpui-base";
import { hc, shared, setShared } from "herdr";

const KEY = "inbox.asks";
// 止まってから読むまでの間 (ms)。質問の描画が状態の報告より遅れても拾えるように
const WAIT = 1000;
// 読み始めてからこれだけ経っても置かれていなければ、その後の描画で読み直す (ms)。読んでいる mod が閉じると、その読みは途切れる。読めなかった時も置かない
const STALE = 10000;

// 左バーの抜粋の見た目。一覧の下に敷いた絵の顔に被らないよう、短く切る
const LINES = 2;
// 1 行に入る字数の目安。全角を 2 と数え、LINES 行分を超えたら … で切る。読み違えて溢れた分は LINES 行の高さで切る
const COLUMNS = 32;
const SIZE = 11.5;
const LEADING = 15;
// 字の左端を、行の icon の右の名前に揃える
const INDENT = 33;
// 地の色。t.chrome の後に付ける alpha ("cc" 等)。null は塗らない
const FILL = null;

// 全角に数える字: CJK の記号、かな、漢字、ハングル、全角の英数と記号
const WIDE = /[\u3000-\u9fff\uac00-\ud7af\uf900-\ufaff\uff00-\uff60]/;

// app を起動し直すと seq を 0 から数え直すので、前の起動で置いた物は seq が合っても使えない。見分けも付かないので、mod ごとに起動して最初の 1 度は、置いてある物を全て捨てて読み直す
let started = false;

// 止まっている agent の画面の最後の数行。たいていは質問か、許可を求める prompt
// 質問とその選択肢が続いている時は、質問から始める
export function snippet(text) {
  const lines = (text ?? "").split("\n")
    .map(l => l.replace(/[│─╭╮╰╯┌┐└┘├┤┬┴┼═║▔▁▏▕]/g, " ").replace(/\s+/g, " ").trim())
    .filter(l => /[\p{L}\p{N}]/u.test(l));
  const tail = lines.slice(-8), asked = tail.findLastIndex(l => /[?？]$/.test(l));
  return (asked >= 0 ? tail.slice(asked) : lines.slice(-4)).join(" · ").slice(0, 240);
}

// list は止まっている agent を全て含む物 (agents() 等)。含まれない agent の抜粋は捨てる
// 止まっている agent の画面を、その止まり方でまだ読んでいなければ読む。seq は agent の状態が変わるたびに上がるので、一度動いてまた止まった agent は読み直す
export function readAsks(cx, list) {
  const blocked = list.filter(a => a.status === "blocked");
  const stored = shared(KEY);
  const asks = Object.fromEntries(Object.entries(started ? stored ?? {} : {}).filter(([address]) => blocked.some(a => a.address === address)));
  started = true;
  const now = Date.now();
  const due = blocked.filter(a => asks[a.address]?.seq !== a.seq || asks[a.address].text === null && now - asks[a.address].at >= STALE);
  for (const a of due) asks[a.address] = { seq: a.seq, text: null, at: now };
  if (JSON.stringify(asks) !== JSON.stringify(stored)) setShared(KEY, asks);
  for (const a of due) {
    cx.spawn(async cx => {
      await cx.sleep(WAIT);
      const r = await hc(["read", a.address, "--lines", "40"]).catch(() => null);
      // 読んでいる間に動き出した agent と、STALE 経って別の読みに引き継がれた agent には置かない
      const ask = shared(KEY)?.[a.address];
      if (r?.code !== 0 || ask?.seq !== a.seq || ask.at !== now || ask.text !== null) return;
      setShared(KEY, { ...shared(KEY), [a.address]: { seq: a.seq, text: snippet(r.stdout), at: now } });
    });
  }
}

// a の今の止まり方で読んだ抜粋。読み終えていない間と、質問らしい行が無かった時は null
export function askOf(a) {
  const ask = shared(KEY)?.[a.address];
  return ask?.seq === a.seq && ask.text ? ask.text : null;
}

function clip(text) {
  const chars = [...text];
  let width = 0;
  for (let i = 0; i < chars.length; i++) {
    width += WIDE.test(chars[i]) ? 2 : 1;
    if (width > LINES * COLUMNS) return `${chars.slice(0, i).join("").trimEnd()}…`;
  }
  return text;
}

// 左バーの agent の行 (el) の下に、抜粋を足す。sidebar を畳んでいる間は足さない
export function withAsk(el, a, t, collapsed) {
  const text = collapsed ? null : askOf(a);
  if (!text) return el;
  return v_flex().flex_none().child(el)
    .child(div().ml(INDENT).mr(8).mb(6).max_h(LINES * LEADING).overflow_hidden().text_size(SIZE).line_height(`${LEADING}px`).text_color(t.muted)
      .when(FILL !== null, d => d.rounded(4).bg(t.chrome + FILL))
      .child(clip(text)));
}
