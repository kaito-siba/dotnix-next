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
      };

      xdg.configFile."nvim" = {
        source = ./config;
        recursive = true;
      };
    };
}
