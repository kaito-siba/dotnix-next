{
  flake.modules.homeManager."dev/web" =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        vtsls # LazyVim's lang.typescript extra defaults to vtsls
        vscode-langservers-extracted # eslint, cssls, html
        nodejs
      ];
    };
}
