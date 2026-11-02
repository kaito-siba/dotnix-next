-- Nix: LazyVim's lang.nix extra (config/lazy.lua) wires up nil_ls. nixd
-- replaces it because it can evaluate this flake and complete NixOS and
-- home-manager options, which nil cannot. The binary comes from
-- modules/dev/nix.nix.
--
-- Options are taken from the albiflora configuration as a representative
-- host; the option set is near-identical across hosts and evaluating one is
-- enough. The flake is located through $HOME so the same config works for
-- every user / host checkout.
local flake = '(builtins.getFlake ("' .. os.getenv("HOME") .. '/repos/github.com/kaito-siba/dotnix-next"))'
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nil_ls = { enabled = false },
        nixd = {
          settings = {
            nixd = {
              nixpkgs = { expr = flake .. ".inputs.nixpkgs.legacyPackages.${builtins.currentSystem}" },
              formatting = { command = { "nixfmt" } },
              options = {
                nixos = { expr = flake .. ".nixosConfigurations.albiflora.options" },
                ["home-manager"] = {
                  expr = flake .. ".nixosConfigurations.albiflora.options.home-manager.users.type.getSubOptions []",
                },
              },
            },
          },
        },
      },
    },
  },
}
