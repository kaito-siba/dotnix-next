// 返事を待っている agent の画面の最後を読んで、質問の抜粋を shared の "inbox.asks" に { [address]: { seq, text, at } } で置く
// text が null の間は、at (ms) に読み始めて、まだ読み終えていない。どちらの mod が読んでいるかは問わない
// 2 つの mod が読み込む (../../_app-home.nix が両方へ写す)
//   cheki-agents  いつも出ている左バーの Agents の一覧。止まった agent をすぐ読みに行き、行の下に抜粋を出す
//   inbox         開いている間だけ生きるモーダル (./main.js)。置かれた抜粋を使い、無い時だけ自分で読みに行く
import { hc, shared, setShared } from "herdr";

const KEY = "inbox.asks";
// 止まってから読むまでの間 (ms)。質問の描画が状態の報告より遅れても拾えるように
const WAIT = 1000;
// 読み始めてからこれだけ経っても置かれていなければ、その後の描画で読み直す (ms)。読んでいる mod が閉じると、その読みは途切れる。読めなかった時も置かない
const STALE = 10000;

// 左バーの抜粋の長さ。一覧が下のチェキに届かないよう、短く切る
const LINES = 2;
// 1 行に入る字数の目安。全角を 2 と数え、LINES 行分を超えたら … で切る。読み違えて溢れた分は、左バーが LINES 行の高さで切る
const COLUMNS = 32;

// 全角に数える字: CJK の記号、かな、漢字、ハングル、全角の英数と記号
const WIDE = /[\u3000-\u9fff\uac00-\ud7af\uf900-\ufaff\uff00-\uff60]/;

// app を起動し直すと seq を 0 から数え直すので、前の起動で置いた物は seq が合っても使えない。見分けも付かないので、mod ごとに起動して最初の 1 度は、置いてある物を全て捨てて読み直す
let started = false;

// 選ぶ画面の操作の案内、質問の見出しの札 (☐ 次)、hc の注記。質問の中身ではないので拾わない
// 操作の案内は Claude Code の画面の字。Claude Code を上げて消えたら build が落ちる (../../task-notes.nix の claudeCodeMarks)。ここを変えたら、そちらも合わせる
const CHROME = /^(?:\d+\.\s*)?(?:Type something\.?|Chat about this)$|Enter to (?:select|confirm)|to navigate|Esc to cancel|^\[hc\]|^[☐☒☑✔←→]/;

// 止まっている agent の画面の最後の数行。たいていは質問か、許可を求める prompt
// 質問があれば、質問と番号の付いた選択肢だけを拾う。選ぶ画面は選択肢の説明と操作の案内で質問の後ろが長くなるので、質問は下から 30 行まで探す
export function snippet(text) {
  // 枠の罫線と選択中の印を落とす。字の無い行は、段落の切れ目として空にして残す
  const lines = (text ?? "").split("\n")
    .map(l => l.replace(/[│─╭╮╰╯┌┐└┘├┤┬┴┼═║▔▁▏▕]/g, " ").replace(/\s+/g, " ").trim().replace(/^[❯›]\s*/, ""))
    .map(l => /[\p{L}\p{N}]/u.test(l) && !CHROME.test(l) ? l : "")
    .slice(-30);
  const asked = lines.findLastIndex(l => /[?？]$/.test(l));
  if (asked < 0) return lines.filter(Boolean).slice(-4).join(" · ").slice(0, 240);
  // 質問が折り返されていれば、同じ段落の前の 2 行まで足す。選択肢の説明の行は落とす
  let start = asked;
  while (start > asked - 2 && lines[start - 1]) start--;
  const options = lines.slice(asked + 1).filter(l => /^\d+\.\s/.test(l));
  return [lines.slice(start, asked + 1).join(" "), ...options].join(" · ").slice(0, 240);
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

// 左バーに出す長さに切った抜粋
export function clip(text) {
  const chars = [...text];
  let width = 0;
  for (let i = 0; i < chars.length; i++) {
    width += WIDE.test(chars[i]) ? 2 : 1;
    if (width > LINES * COLUMNS) return `${chars.slice(0, i).join("").trimEnd()}…`;
  }
  return text;
}
