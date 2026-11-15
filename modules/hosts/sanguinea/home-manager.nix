{ lib, ... }:
{
  flake.modules.nixos."hosts/sanguinea" = {
    home-manager.useUserPackages = true;
    home-manager.backupFileExtension = "backup";

    home-manager.users.w963n =
      { pkgs, ... }:
      {
        # Tap-to-click is disabled on this touchpad, so drop the shared `tap`.
        xdg.configFile."niri/config.kdl".source = lib.mkForce (
          pkgs.writeText "sanguinea-niri-config.kdl" (
            lib.replaceStrings [ "        tap\n" ] [ "" ] (
              builtins.readFile ../../desktop/linux/niri/config/config.kdl
            )
            # クラムシェル運用: 蓋を閉じても suspend しないので、内蔵パネルは自前で消す。
            + ''

              switch-events {
                  lid-close { spawn "niri" "msg" "output" "eDP-1" "off"; }
                  lid-open { spawn "niri" "msg" "output" "eDP-1" "on"; }
              }
            ''
          )
        );

        # Monitor layout for this host's displays.
        xdg.configFile."niri/outputs.kdl".source = lib.mkForce ./niri-outputs.kdl;
      };
  };
}
