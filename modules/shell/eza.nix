{
  flake.modules.homeManager.shell = {
    programs.eza = {
      enable = true;
      icons = "auto";
    };

    programs.zsh.shellAliases = {
      ls = "eza --icons -lag";
    };
  };
}
