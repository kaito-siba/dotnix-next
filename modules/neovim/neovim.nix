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
