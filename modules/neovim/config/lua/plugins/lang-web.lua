-- Toolchain comes from modules/dev/web.nix
return {
  { import = "lazyvim.plugins.extras.lang.typescript" },
  { import = "lazyvim.plugins.extras.linting.eslint" },

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
