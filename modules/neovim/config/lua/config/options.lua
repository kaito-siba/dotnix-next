-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- lang.php extra defaults to phpactor; we ship intelephense (modules/dev/php.nix)
vim.g.lazyvim_php_lsp = "intelephense"

-- クリップボード: yank を host の Wayland クリップボード (wl-copy) と
-- OSC 52 の両方へ流す。
--
-- herdr の pane は GUI セッションの env を継承するため、`herdr --remote`
-- で ssh 越しに attach しても pane 内に SSH_TTY が入らず、pane 側からは
-- 「今リモートから触っているか」を判定できない。そこで常に両方へ書き、
--   - host 側:   wl-copy (内容は wl-clip-persist が保持し続ける)
--   - 手元の端末: OSC 52 → herdr が attach 中のクライアントへ転送
-- の双方にクリップボードを載せる。
--
-- paste は OSC 52 read を使うと ghostty の clipboard-read = ask で毎回
-- 確認ダイアログが出るため wl-paste 固定。
if vim.env.WAYLAND_DISPLAY and vim.fn.executable("wl-copy") == 1 then
  local function copy(reg)
    local osc52 = require("vim.ui.clipboard.osc52").copy(reg)
    local argv = reg == "*" and { "wl-copy", "--primary", "--type", "text/plain" }
      or { "wl-copy", "--type", "text/plain" }

    return function(lines, regtype)
      -- UI 未接続 (nvim --headless) では nvim_ui_send が失敗するので無視する
      pcall(osc52, lines, regtype)
      vim.system(argv, { stdin = table.concat(lines, "\n") })
    end
  end

  vim.g.clipboard = {
    name = "wl-copy + OSC 52",
    copy = { ["+"] = copy("+"), ["*"] = copy("*") },
    paste = {
      ["+"] = { "wl-paste", "--no-newline" },
      ["*"] = { "wl-paste", "--no-newline", "--primary" },
    },
  }
end
