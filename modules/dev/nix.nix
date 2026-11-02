{
  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # nixd rather than nil: it evaluates this flake to complete NixOS /
        # home-manager options. The neovim side (plugins/lang-nix.lua) disables
        # the nil_ls that LazyVim's lang.nix extra would otherwise start.
        nixd
        nixfmt
        statix
        deadnix
      ];
    };
}
