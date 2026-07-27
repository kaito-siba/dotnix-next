{
  flake.modules.homeManager.shell =
    { lib, ... }:
    {
      programs.eza = {
        enable = true;
        icons = "auto";
      };

      programs.zsh.shellAliases = {
        ls = "eza --icons -lag";
      };

      # shellAliases は .zshrc 内で initContent より後に書かれるため、
      # alias 定義の後ろに来るよう mkAfter で無効化する
      programs.zsh.initContent = lib.mkAfter ''
        # AIエージェントのシェルには標準コマンドをそのまま使わせる
        # （ls=eza などの置き換えは出力形式が変わりエージェントが誤動作する）
        if [[ -n "$CLAUDECODE" ]]; then
          unalias ls 2>/dev/null
        fi
      '';
    };
}
