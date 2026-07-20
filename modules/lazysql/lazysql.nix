{
  # A database TUI is desktop tooling, so it stands on its own rather than
  # riding along with every host that imports shell.
  flake.modules.homeManager.lazysql =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.lazysql ];

      programs.zsh.shellAliases = {
        lq = "lazysql";
      };
    };
}
