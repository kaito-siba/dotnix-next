{
  flake.modules.homeManager.shell = {
    programs.fzf = {
      enable = true;
      enableZshIntegration = true;

      # catppuccin latte, matching the starship palette.
      defaultOptions = [
        "--color=bg+:#ccd0da,spinner:#dc8a78,hl:#d20f39"
        "--color=fg:#4c4f69,header:#d20f39,info:#8839ef,pointer:#dc8a78"
        "--color=marker:#7287fd,fg+:#4c4f69,prompt:#8839ef,hl+:#d20f39"
        "--color=selected-bg:#bcc0cc"
        "--multi"
      ];
    };
  };
}
