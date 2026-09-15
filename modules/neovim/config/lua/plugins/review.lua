-- Code review inside nvim: annotate a diff and export the comments as markdown.
-- nui.nvim / codediff.nvim are hard requirements, declared as dependencies so
-- lazy.nvim installs them; they need no config of their own.
return {
  "georgeguimaraes/review.nvim",
  version = "v*",
  dependencies = {
    "esmuellert/codediff.nvim",
    "MunifTanjim/nui.nvim",
  },
  cmd = { "Review" },
  keys = {
    { "<leader>r", "<cmd>Review<cr>", desc = "Review working tree" },
    { "<leader>R", "<cmd>Review commits<cr>", desc = "Review commits" },
  },
  opts = {},
}
