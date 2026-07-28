{
  flake.modules.homeManager.shell =
    {
      home,
      pkgs,
      config,
      ...
    }:
    {
      programs = {
        git = {
          enable = true;
          settings = {
            user = {
              name = "k-nanchi";
              email = "kaito@siba-service.jp";
            };
          };
          lfs.enable = true;
          ignores = [
            ".direnv/"
            ".DS_Store"
          ];
        };

        difftastic = {
          enable = true;
          git = {
            enable = true;
            diffToolMode = true;
          };
        };

        zsh.shellAliases = {
          lg = "lazygit";
        };

        zsh.plugins = [
          {
            name = "zsh-ghq-fzf";
            src = ./.;
            file = "zsh-ghq-fzf.plugin.zsh";
          }
          {
            name = "zsh-git-worktree-fzf";
            src = ./.;
            file = "zsh-git-worktree-fzf.plugin.zsh";
          }
        ];

        lazygit = {
          enable = true;
          settings = {
            git = {
              pagers = [
                {
                  colorArg = "always";
                  externalDiffCommand = "difft --color=always --display=inline --syntax-highlight=on --tab-width=2";
                }
              ];
            };
          };
        };
      };

      home.packages = [ pkgs.ghq ];
      home.sessionVariables.GHQ_ROOT = "${config.home.homeDirectory}/repos";
    };
}
