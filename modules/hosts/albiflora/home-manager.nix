{ lib, ... }:
{
  flake.modules.nixos."hosts/albiflora" = {
    # Keep home.packages in /etc/profiles/per-user as before the migration.
    home-manager.useUserPackages = true;

    # Pre-migration dotfiles are kept next to the generated ones.
    home-manager.backupFileExtension = "backup";

    home-manager.users.w963n = {
      # This home was created on 25.05; keep it pinned like the system.
      home.stateVersion = lib.mkForce "25.05";

      # Monitor layout for this host's displays.
      xdg.configFile."niri/outputs.kdl".source = lib.mkForce ./niri-outputs.kdl;
    };
  };
}
