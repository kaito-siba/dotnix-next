{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      # niri 26.04 (nixpkgs 収録) で blur が入ったため、flake input からの
      # ソースビルドをやめ binary cache の効く nixpkgs 版を使う。
      programs.niri.enable = true;

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
