-- Cross cutting formats: config files, documentation and shell glue.
-- The LazyVim extras for these live in config/lazy.lua (import order matters).
-- Toolchain comes from modules/dev/common.nix. When a host does not enable that
-- module the binaries are simply absent from PATH and the servers never start.
return {
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
