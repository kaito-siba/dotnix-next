-- Nix: LazyVim's lang.nix extra (config/lazy.lua) wires up nil_ls. nixd
-- replaces it because it can evaluate this flake and complete NixOS and
-- home-manager options, which nil cannot. The binary comes from
-- modules/dev/nix.nix.
--
-- Two things are host specific and come from outside this file: the flake
-- checkout path is NH_FLAKE (set by the nh configuration, the single place
-- that knows it), and the configuration to evaluate is written by
-- modules/dev/nix.nix into lua/dotnix/host.lua at switch time. Without
-- either, nixd still runs with nixpkgs completion only.
local flake_path = os.getenv("NH_FLAKE")
local ok, host = pcall(require, "dotnix.host")

local settings = {
  formatting = { command = { "nixfmt" } },
}
if flake_path then
  local flake = '(builtins.getFlake "' .. flake_path .. '")'
  settings.nixpkgs = { expr = flake .. ".inputs.nixpkgs.legacyPackages.${builtins.currentSystem}" }
  if ok and host then
    local cfg = flake .. "." .. host.configurations .. "." .. host.name
    settings.options = {
      nixos = { expr = cfg .. ".options" },
      ["home-manager"] = { expr = cfg .. ".options.home-manager.users.type.getSubOptions []" },
    }
  end
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nil_ls = { enabled = false },
        nixd = { settings = { nixd = settings } },
      },
    },
  },
}
