{
  flake.modules.homeManager.shell =
    { ... }:
    {
      programs.git = {
        enable = true;
        settings = {
          user = {
            name = "k-nanchi";
            email = "kaito@siba-service.jp";
          };
        };
        lfs.enable = true;
        ignores = [
          ".envrc"
          ".direnv/"
        ];
      };

      programs.delta = {
        enable = true;
        enableGitIntegration = true;
      };

      programs.zsh.shellAliases = {
        lg = "lazygit";
      };

      programs.lazygit = {
        enable = true;
        settings = {
          git = {
            pagers = [
              {
                colorArg = "always";
                pager = "delta --paging=never";
              }
            ];
          };
        };
      };
    };
}
