{
  flake.modules.homeManager.aws =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        awscli2
        ssm-session-manager-plugin
        stu # S3 TUI
      ];
    };
}
