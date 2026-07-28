{
  flake.modules.homeManager."dev/nix" =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        nil # LazyVim's lang.nix extra configures nil_ls
        nixd
        nixfmt
        statix
        deadnix
        devbox
      ];
    };
}
