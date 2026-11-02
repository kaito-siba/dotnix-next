{
  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        vtsls # LazyVim's lang.typescript extra defaults to vtsls
        nodejs
      ];
    };
}
