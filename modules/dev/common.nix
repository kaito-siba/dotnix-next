{
  # Tooling for formats that show up across every language: config files,
  # documentation and shell glue.
  #
  # dev/* modules only put toolchains on PATH and deliberately know nothing
  # about any editor. Editor side configuration lives in modules/neovim.
  flake.modules.homeManager."dev/common" =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # json / yaml / toml
        vscode-langservers-extracted # jsonls
        yaml-language-server
        taplo

        # markdown
        marksman
        markdownlint-cli2

        # shell
        bash-language-server
        shfmt
        shellcheck

        # shared formatter for json / yaml / markdown / web
        prettierd
      ];
    };
}
