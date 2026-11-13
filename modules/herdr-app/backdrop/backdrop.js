// Agents の一覧の下に薄く敷く絵。agents mod の写しに差し込んで使う (../_show.nix)。
// 画像は repo に入れず、app home の backgrounds/sidebar.png に置く。無ければ何も
// 出ない。
import { div, image } from "gpui-kit";
import { settings } from "herdr";

const FILE = "backgrounds/sidebar.png";
// 画像の縦横比 (幅 1066 : 高さ 1736)。画像を差し替えたら、ここも合わせる。
const RATIO = 1736 / 1066;
// 絵の幅は sidebar の幅の何倍か。sidebar より広くして、はみ出た分を切る。
const SCALE = 1.75;
// 絵の幅のうち、左へはみ出させる割合。大きいほど絵が左へ寄る。
const LEFT = 0.067;
// 絵の高さのうち、下へ隠す割合。
const BELOW = 0.106;
const OPACITY = 0.28;
// 一覧の見出しの高さ。絵の上端をこれより上へ出さない。
const HEADER = 41;

// area は mod の根の大きさ ({ width, height })。まだ分からない間は何も出さない。
export function backdrop(area) {
  if (!area) return div();
  // area は zoom を掛けた後の大きさで届くが、mod の中の長さには zoom がもう一度
  // 掛かる。割り戻しておかないと、絵が zoom の分だけ小さく (大きく) なる。
  const zoom = settings().zoom || 1, w = area.width / zoom, h = area.height / zoom;
  // 枠が低い時は、顔が上で切れないように絵を縮める。
  const width = Math.min(w * SCALE, (h - HEADER) / (1 - BELOW) / RATIO);
  const height = width * RATIO;
  return image(FILE).absolute().left(-width * LEFT).bottom(-height * BELOW).w(width).h(height).opacity(OPACITY);
}
