{
  flake.modules.homeManager."dev/nix" =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        nil # LazyVim's lang.nix extra configures nil_ls
        nixfmt
        statix
        deadnix
      ];
    };
}
