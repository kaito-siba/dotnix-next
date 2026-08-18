-- Toolchain comes from modules/dev/web.nix
-- The LazyVim extras (typescript / eslint) live in config/lazy.lua.
return {
  -- css / html have no LazyVim extra
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        cssls = {},
        html = {},
      },
    },
  },
}
