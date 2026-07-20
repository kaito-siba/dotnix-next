{
  flake.modules = {
    homeManager.shell = {
      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autocd = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;
        setOptions = [
          "AUTO_LIST"
          "AUTO_MENU"
        ];
      };
    };

    # TRANSITIONAL: preserves the hand-managed zsh config under ~/.config/zsh.
    # ZDOTDIR has to be exported from /etc/zshenv, before zsh goes looking for
    # the user's own zshenv, so it cannot come from home-manager; nix-darwin's
    # generated /etc/zshenv sources this file at the end.
    #
    # Drop this once home-manager's programs.zsh owns the config and writes the
    # dotfiles itself.
    darwin.shell = {
      environment.etc."zshenv.local".text = ''
        export ZDOTDIR="$HOME"/.config/zsh
      '';
    };
  };
}
