{ lib, ... }:
{
  flake.modules.nixos."hosts/radiata" = {
    # This host was installed on 24.11; never bump stateVersion in place.
    system.stateVersion = lib.mkForce "24.11";

    programs.nh.flake = "/home/rkv12/ghq/github.com/kaito-siba/dotnix-next";

    # Auto-login target for the tuigreet session configured in modules/niri.
    services.greetd.settings.initial_session.user = "rkv12";

    # radiata 専用の overlay: tailscale のテストスキップを追加
    # https://github.com/tailscale/tailscale/issues/16966
    nixpkgs.overlays = [
      (_: prev: {
        tailscale = prev.tailscale.overrideAttrs (old: {
          checkFlags = builtins.map (
            flag:
            if prev.lib.hasPrefix "-skip=" flag then
              flag + "|^TestGetList$|^TestIgnoreLocallyBoundPorts$|^TestPoller$"
            else
              flag
          ) old.checkFlags;
        });
      })
    ];
  };
}
