{
  flake.modules.nixos."hosts/sanguinea" = {
    programs.nh.flake = "/home/w963n/repos/github.com/kaito-siba/dotnix-next";

    # Auto-login target for the tuigreet session configured in modules/desktop.
    services.greetd.settings.initial_session.user = "w963n";
  };
}
