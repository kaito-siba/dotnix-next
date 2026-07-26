-- Follow the system appearance, matching ghostty's
-- `theme = dark:Catppuccin Mocha, light:Catppuccin Latte` (modules/ghostty/config.ghostty).
local function apply()
  vim.cmd.colorscheme("catppuccin")
end

return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      -- "auto" resolves the flavour from vim.o.background at load time.
      flavour = "auto",
      background = {
        light = "latte",
        dark = "mocha",
      },
    },
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },

  {
    -- Neither macOS nor the freedesktop portal pushes appearance changes into a
    -- running process, so this polls: `defaults read -g AppleInterfaceStyle` on
    -- darwin, org.freedesktop.appearance.color-scheme over dbus on linux.
    "f-person/auto-dark-mode.nvim",
    lazy = false,
    priority = 1000,
    init = function()
      -- LazyVim hands bufferline its highlights via
      -- `catppuccin.special.bufferline.get_theme()`, and bufferline resolves
      -- them exactly once, when it loads on VeryLazy. That happens before the
      -- first (asynchronous) appearance poll lands, so catppuccin has no
      -- resolved flavour yet and the palette falls back to mocha -- a black
      -- tab bar above a latte buffer. Re-applying the colorscheme once
      -- everything is up re-resolves them.
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        once = true,
        callback = function()
          vim.schedule(apply)
        end,
      })
    end,
    opts = {
      update_interval = 3000,
      -- Assume dark over SSH/TTY, where the query has nothing to answer with.
      fallback = "dark",
      -- Setting vim.o.background alone is not enough: catppuccin picks its
      -- flavour when it loads, so the colorscheme has to be re-applied.
      set_dark_mode = function()
        vim.o.background = "dark"
        apply()
      end,
      set_light_mode = function()
        vim.o.background = "light"
        apply()
      end,
    },
  },
}
