// mod が開く folder を、pane で動く agent が今居る所に合わせる。agent の居場所は、その machine の task-notes where に訊く (./task-notes.py)
// pane の folder では足りない: Claude Code は EnterWorktree で worktree へ移り、sbx の sandbox の中の agent の folder は host の process から見えない
// mod は自分の folder の外を import できないので、nix がこの file を使う mod の folder へコピーする (../_show.nix)
import { spaces, panes, focused, exec } from "herdr";

// focus している pane の場所。where で agent の居場所が分からない時は、この cwd と branch を使う
export function location() {
  const space = spaces().find(s => s.active), f = focused();
  const pane = f?.pane ? panes().find(p => p.pane === f.pane) : null;
  return { cwd: pane?.cwd || f?.cwd || space?.folder, on: space?.machine ?? null, terminal: f?.terminal ?? pane?.terminal ?? null, branch: pane?.branch ?? space?.branch ?? null };
}

// place.terminal の agent が今居る folder を訊き、place に重ねて返す。branch と root は、その folder の checkout の物
// source は agent の種類 ("claude"、"sbx"、agent の無い "pane")、session は分かれば Claude Code の session id。訊けなければ、どちらも付かない
export async function where(place) {
  const { terminal, on } = place;
  if (!terminal) return place;
  try {
    // 他の machine の端末には "<machine>/" が前に付く。その machine の上では付かない
    const id = on && terminal.startsWith(`${on}/`) ? terminal.slice(on.length + 1) : terminal;
    const found = JSON.parse((await exec("task-notes", ["where", id], { on, timeout: 5000 })).stdout);
    if (found.cwd) return { ...place, ...found };
  } catch {}
  return place;
}
