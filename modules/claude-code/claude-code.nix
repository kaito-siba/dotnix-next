{
  nixpkgs.allowedUnfreePackages = [ "claude-code" ];

  # 以前は sadjow/claude-code-nix の latest を追っていたが、出たての版を即座に
  # 取り込むので冷却期間の方針と合わない。nixpkgs-unstable は bot が頻繁に
  # bump していて遅れは数日程度。stable (26.05) は追従が遅いので unstable から取る。
  flake.modules.homeManager.claude-code =
    { pkgs-unstable, ... }:
    {
      programs.claude-code = {
        enable = true;
        package = pkgs-unstable.claude-code;
      };
    };
}
