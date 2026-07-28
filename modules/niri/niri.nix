{
  flake.modules.nixos.niri =
    { inputs, pkgs, ... }:
    {
      programs.niri = {
        enable = true;
        package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri;
      };

      programs.uwsm = {
        enable = true;
        waylandCompositors = {
          niri = {
            prettyName = "Niri";
            comment = "Niri compositor managed by UWSM";
            binPath = "/run/current-system/sw/bin/niri-session";
          };
        };
      };

      xdg.portal = {
        enable = true;
        extraPortals = with pkgs; [ xdg-desktop-portal-gnome ];
      };

      environment.systemPackages = with pkgs; [
        # https://yalter.github.io/niri/Xwayland.html#using-xwayland-satellite
        xwayland-satellite
      ];
    };
}
