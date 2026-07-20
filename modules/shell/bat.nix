{
  flake.modules.homeManager.shell = {
    programs.bat.enable = true;

    programs.zsh.shellAliases = {
      cat = "bat -pP";
    };
  };
}
