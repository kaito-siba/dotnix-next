// 左バーの Agents (./main.js) と右パネルの Tasks (../tasks) が分け合う、色と字と状態の印
// mod は自分の folder の外を import できないので、nix がこの file を使う mod の folder へコピーする (../../_show.nix)
import { div, svg } from "gpui-kit";

// cheki-agents の ./fonts に同梱する M PLUS Rounded 1c。app が mod の fonts から読む。font の中の family の名前は "Rounded Mplus 1c"
export const ROUND = "Rounded Mplus 1c";

// theme に無い差し色。accent は見出し、符丁、focus の枠、水玉、テープ、チェキの字。call は呼んでいる agent
// dark (lycoreco-takina の紺の地) は千束の赤を淡くした桃、light (lycoreco-chisato の桃色の地) はたきなの制服の紺を差す。赤い地に赤では見えにくいので
// light の字の色は、白い地で読めるように濃くしてある
const DARK = {
  accent: "#ff8fab", accentBg: "#ff8fab24", onBg: "#ff8fab12", call: "#ff8fab", callBg: "#ff8fab24",
  run: "#ffe27a", runBg: "#ffe27a1c", done: "#7ce0c3", doneBg: "#7ce0c31c", idle: "#b7a6ff", idleBg: "#b7a6ff1a",
  dots: "#ff8fab1a", frame: "#f6efe6", ink: "#c23a44", date: "#9c7a85", tape: "#ff8fab8c", shadow: "#00000033", photo: 0.92, photoBg: "#1b2a4a",
};
const LIGHT = {
  accent: "#2b4b88", accentBg: "#2b4b881f", onBg: "#2b4b880f", call: "#c8325a", callBg: "#f0555a1c",
  run: "#8a6500", runBg: "#ffd84d38", done: "#007d76", doneBg: "#3dbf8024", idle: "#7158c2", idleBg: "#b7a6ff2e",
  dots: "#2b4b8814", frame: "#ffffff", ink: "#2b4b88", date: "#9c7a85", tape: "#2b4b884d", shadow: "#7a566824", photo: 1, photoBg: "#e9dfe6",
};

// 端末の地の明るさで、dark と light のどちらの差し色を使うか決める
export function palette(t) {
  const hex = (t.background ?? "#000000").replace("#", "");
  const [r, g, b] = [0, 2, 4].map(i => parseInt(hex.slice(i, i + 2), 16) / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.5 ? LIGHT : DARK;
}

export const WORD = { blocked: "CALLING", working: "RUNNING", done: "DONE", idle: "STANDBY" };
// 状態ごとの字の色と地の色
export const tone = (c, st) => ({ blocked: [c.call, c.callBg], working: [c.run, c.runBg], done: [c.done, c.doneBg] })[st] ?? [c.idle, c.idleBg];

// 状態が変わってからの時間。1 日までは時:分、その先は日
export function clock(ms) {
  const m = Math.max(0, Math.floor(ms / 60000));
  return m >= 1440 ? `${Math.floor(m / 1440)}d` : `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
}

// 符丁の頭: space の名前の語の頭文字 (knowledge-portal → KP)。1 語なら頭の 2 字
export function initials(name) {
  const words = (name ?? "").split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  const head = words.length > 1 ? words.slice(0, 3).map(w => [...w][0]).join("") : [...(words[0] ?? "?")].slice(0, 2).join("");
  return head.toUpperCase();
}

// 状態の印。呼んでいる時は電話、作業中は回る輪、終わった時は check、待機は空の輪
export function mark(st, ink) {
  if (st === "blocked") return svg("mods/cheki-agents/phone.svg").size(11).flex_none();
  if (st === "working") return svg("mods/workspace-chrome/spinner.svg").size(11).flex_none().spin(900);
  if (st === "done") return svg("mods/workspace-chrome/check.svg").size(11).flex_none();
  return div().size(8).mx(1.5).flex_none().rounded(4).border(1.5).border_color(ink);
}
