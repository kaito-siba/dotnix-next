{
  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        pyright # LazyVim's lang.python extra defaults to pyright
        ruff
        python3
        uv
      ];
    };
}
