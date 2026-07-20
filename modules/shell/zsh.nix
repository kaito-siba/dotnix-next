{
  flake.modules.homeManager.shell =
    { config, ... }:
    {
      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autocd = true;

        # Keep the shell's own dotfiles out of $HOME. home-manager writes a
        # ~/.zshenv that exports ZDOTDIR and hands off to this directory, so no
        # system-level ZDOTDIR is needed.
        dotDir = "${config.home.homeDirectory}/.config/zsh";

        autosuggestion = {
          enable = true;
          highlight = "fg=5";
        };
        syntaxHighlighting.enable = true;

        setOptions = [
          "AUTO_LIST"
          "AUTO_MENU"
        ];

        history = {
          path = "${config.xdg.stateHome}/zsh/history";
          size = 10000;
          save = 10000;
          append = true;
          ignoreDups = true;
          ignoreAllDups = true;
        };

        completionInit = ''
          autoload -Uz compinit
          compinit -d "${config.xdg.cacheHome}/zsh/zcompdump-$ZSH_VERSION"

          # Let lowercase input match uppercase candidates.
          zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
          # Walk the candidate list with Tab and the arrow keys.
          zstyle ':completion:*:default' menu select=1
        '';

        initContent = ''
          # Move by word with alt-left / alt-right.
          bindkey '^[[1;3D' backward-word
          bindkey '^[[1;3C' forward-word
        '';
      };

      home.sessionPath = [ "$HOME/.local/bin" ];
    };
}
