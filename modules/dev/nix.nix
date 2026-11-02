{
  flake.modules.homeManager.dev =
    {
      pkgs,
      hostConfig,
      ...
    }:
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

      # Which configuration nixd should evaluate for option completion: this
      # host's. The flake path itself comes from NH_FLAKE, the same variable
      # nh uses, so there is one place that knows where the checkout lives.
      xdg.configFile."nvim/lua/dotnix/host.lua".text = ''
        return {
          name = "${hostConfig.name}",
          configurations = "${
            if pkgs.stdenv.hostPlatform.isDarwin then "darwinConfigurations" else "nixosConfigurations"
          }",
        }
      '';
    };
}
