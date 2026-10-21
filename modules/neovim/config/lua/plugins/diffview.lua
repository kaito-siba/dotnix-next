-- Side-by-side git diff and file history viewer.
-- LazyVim already claims <leader>gd (hunk picker), <leader>gf (lazygit file
-- history) and <leader>gh* (gitsigns hunks), so diffview lives under <leader>gv.
return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
  keys = {
    {
      "<leader>gv",
      function()
        local lib = require("diffview.lib")
        if lib.get_current_view() then
          vim.cmd("DiffviewClose")
        else
          vim.cmd("DiffviewOpen")
        end
      end,
      desc = "Diffview (toggle)",
    },
    { "<leader>gV", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview file history (current file)" },
    { "<leader>gV", ":'<,'>DiffviewFileHistory<cr>", mode = "v", desc = "Diffview history (selection)" },
    { "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview history (repo)" },
    -- Changes on the current branch relative to its merge-base with the
    -- default branch, i.e. what a PR would show. Needs origin/HEAD to exist
    -- (`git remote set-head origin -a` if it doesn't).
    { "<leader>gP", "<cmd>DiffviewOpen origin/HEAD...HEAD<cr>", desc = "Diffview PR (vs merge-base)" },
  },
  opts = {
    enhanced_diff_hl = true,
    -- When the right side of a rev range is HEAD, show the working tree
    -- buffers instead of git blobs so LSP (diagnostics, references) works
    -- in the diff buffers. No-op for ranges that don't end at HEAD.
    default_args = {
      DiffviewOpen = { "--imply-local" },
    },
    view = {
      merge_tool = { layout = "diff3_mixed" },
    },
    keymaps = {
      view = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close diffview" } } },
      file_panel = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close diffview" } } },
      file_history_panel = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close diffview" } } },
    },
  },
}
