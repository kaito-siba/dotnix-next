// focus している pane の folder で lazygit を起動し、peek (端末を tab の上に重ねて出す herdr の dialog) で見せる
// key から呼べるのは mod.open だけなので、この mod は lazygit を起動して peek を開いたら自分は閉じる launcher
// 端末を載せた dialog を openOverlay で自分で開く事もできるが、その端末には click するまで key が入らず、mod から focus を当てる手段も無い
import { View, div } from "gpui-kit";
import { spaces, panes, focused, terminals, hc, run, notify, props, closeOverlay } from "herdr";

// 端末の名前は live の間ひとつしか付けられない。これで二重に起動するのを防ぐ
const NAME = "lazygit";

export default class Lazygit extends View {
  init(_props, cx) {
    const space = spaces().find(s => s.active), f = focused();
    const pane = f?.pane ? panes().find(p => p.pane === f.pane) : null;
    const cwd = pane?.cwd || f?.cwd || space?.folder, on = space?.machine ?? null;
    cx.spawn(async cx => {
      let address = null;
      try {
        if (!cwd) throw new Error("No folder");
        // pane を持たない端末として起動する。--no-parent が無いと、終わった事が focus している端末の prompt に書き込まれる
        const r = await hc(["run", "--json", "--bg", "--rm", "--no-parent", "--no-notify", "--name", NAME, "--cwd", cwd, ...(on ? ["--on", on] : []), "--", "lazygit"]);
        // hc は失敗も JSON で返す。成功は stdout、失敗は stderr に出る
        const out = JSON.parse(r.stdout.trim() || r.stderr.trim());
        // もう開いている時に押されたら、lazygit を終わらせて閉じる
        if (out.error?.kind === "name_taken") await hc(["kill", on ? `${on}/${NAME}` : NAME]);
        else if (out.error) throw new Error(out.error.message);
        else {
          address = out.address;
          // app が core から新しい端末を知らされるまで、少し間がある。その前に peek を呼ぶと「動いていない」と断られる
          for (let i = 0; i < 60 && !terminals().some(t => t.address === address); i++) await cx.sleep(50);
        }
      } catch (e) { notify({ title: "lazygit", body: String(e?.message ?? e), level: "error" }); }
      // 自分を先に閉じる。後から閉じると、peek に当たった focus が元の pane へ戻され得る
      closeOverlay(props().overlay);
      if (address) run("terminal.peek", { terminal: address });
    });
  }

  render() { return div(); }
}
