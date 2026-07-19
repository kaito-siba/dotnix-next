{
  flake.modules.homeManager.shell = {
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
}
