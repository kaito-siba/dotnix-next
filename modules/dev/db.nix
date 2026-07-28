{
  # Database client CLIs (servers run elsewhere; these are for poking at them).
  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        postgresql
        mysql84
        mysql-shell
        lazysql
      ];

      programs.zsh.shellAliases = {
        lq = "lazysql";
      };
    };
}
