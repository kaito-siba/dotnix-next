{
  flake.modules.homeManager.shell =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.lazysql ];

      programs.zsh.shellAliases = {
        lq = "lazysql";
      };
    };
}
