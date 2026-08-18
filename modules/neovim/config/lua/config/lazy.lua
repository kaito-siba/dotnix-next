local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- LazyVim extras must come after lazyvim.plugins and before our own
    -- plugins, otherwise spec merging resolves in the wrong order. They are
    -- host independent: servers whose binary is not on PATH are skipped, so
    -- the matching dev/* nix module is optional.
    -- cross cutting formats (modules/dev/common.nix)
    { import = "lazyvim.plugins.extras.formatting.prettier" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.lang.yaml" },
    { import = "lazyvim.plugins.extras.lang.toml" },
    { import = "lazyvim.plugins.extras.lang.markdown" },
    -- nix (modules/dev/nix.nix)
    { import = "lazyvim.plugins.extras.lang.nix" },
    -- python (modules/dev/python.nix)
    { import = "lazyvim.plugins.extras.lang.python" },
    -- rust (modules/dev/rust.nix)
    { import = "lazyvim.plugins.extras.lang.rust" },
    -- web (modules/dev/web.nix)
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.linting.eslint" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  -- rockspec/packspec manifests shipped inside plugin repos can pull in
  -- undeclared plugins as non-optional dependencies (e.g. nvim-dap via
  -- nvim-dap-python's rockspec, which then loads without the dap.core extra
  -- and crashes). Only trust lazy.lua manifests.
  pkg = { sources = { "lazy" } },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  -- the config dir is a read-only nix store path, so the lockfile cannot live there
  lockfile = vim.fn.stdpath("data") .. "/lazy-lock.json",
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
