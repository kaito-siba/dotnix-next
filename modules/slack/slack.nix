{
  nixpkgs.allowedUnfreePackages = [ "slack" ];

  # No configuration to declare, but which hosts need a Slack client varies,
  # so it stays its own module rather than joining a grab-bag app list.
  flake.modules.homeManager.slack =
    { pkgs-unstable, ... }:
    {
      home.packages = [ pkgs-unstable.slack ];
    };
}
