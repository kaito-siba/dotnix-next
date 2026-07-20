{
  flake.modules.homeManager.neovim =
    { pkgs, ... }:
    {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        plugins = with pkgs.vimPlugins; [
          nvim-lspconfig
        ];

        # lua_ls / stylua are configured by LazyVim core regardless of which
        # dev/* module is enabled, so they belong here rather than in dev/lua.
        # Language specific tooling lives in modules/dev/*.nix.
        extraPackages = with pkgs; [
          lua-language-server
          stylua

          # LazyVim tracks the nvim-treesitter "main" branch, which compiles
          # parsers at runtime rather than shipping them. Its documented
          # requirements are a C compiler, tree-sitter-cli >= 0.26.1, and
          # tar + curl. Without these :TSUpdate fails and highlighting is dead.
          gcc
          tree-sitter
          curl
          gnutar
        ];

        withPython3 = false;
        withNodeJs = false;
        withRuby = false;
        withPerl = false;
      };

      xdg.configFile."nvim" = {
        source = ./config;
        recursive = true;
      };
    };
}
