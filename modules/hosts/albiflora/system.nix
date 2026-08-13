{ lib, ... }:
{
  flake.modules.nixos."hosts/albiflora" = {
    # This host was installed on 25.05; never bump stateVersion in place.
    system.stateVersion = lib.mkForce "25.05";

    programs.nh.flake = "/home/w963n/repos/github.com/kaito-siba/dotnix-next";

    # Auto-login target for the tuigreet session configured in modules/desktop.
    services.greetd.settings.initial_session.user = "w963n";
  };
}
