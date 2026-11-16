{
  # Slack の sweep と standup の下書きはこの常駐機で作り、laptop (incarnata) の
  # herdr-app からも読む (modules/work-digest)。
  flake.modules.nixos."hosts/albiflora" = {
    work-digest.user = "w963n";

    home-manager.users.w963n.work-digest.allowedNodes = [ "incarnata" ];
  };
}
