-- LSP servers, formatters and linters come from nix (modules/dev/*.nix),
-- so mason is disabled entirely.
--
-- With mason-lspconfig.nvim absent, LazyVim's lsp module falls back to calling
-- vim.lsp.enable() for every configured server, resolving the binary from $PATH.
--
-- This is what keeps the lang-*.lua files below independent of which dev/*
-- modules a host enables: vim.lsp's can_start() validates that cmd[1] is
-- executable before starting a client, so a server whose binary is missing is
-- skipped silently (it only reaches :LspLog, never vim.notify).
return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "jay-babu/mason-nvim-dap.nvim", enabled = false },
}
