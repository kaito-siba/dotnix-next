-- Cross cutting formats: config files, documentation and shell glue.
-- Toolchain comes from modules/dev/common.nix. When a host does not enable that
-- module the binaries are simply absent from PATH and the servers never start.
return {
  { import = "lazyvim.plugins.extras.formatting.prettier" },
  { import = "lazyvim.plugins.extras.lang.json" },
  { import = "lazyvim.plugins.extras.lang.yaml" },
  { import = "lazyvim.plugins.extras.lang.toml" },
  { import = "lazyvim.plugins.extras.lang.markdown" },

  -- no LazyVim extra covers shell, so configure the server directly
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        bashls = {},
      },
    },
  },
}
