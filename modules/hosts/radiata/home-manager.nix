{ lib, ... }:
{
  flake.modules.nixos."hosts/radiata" = {
    # Keep home.packages in /etc/profiles/per-user as before the migration.
    home-manager.useUserPackages = true;

    # Pre-migration dotfiles are kept next to the generated ones.
    home-manager.backupFileExtension = "backup";

    home-manager.users.rkv12 = {
      # This home was created on 24.11; keep it pinned like the system.
      home.stateVersion = lib.mkForce "24.11";

      # Match the system nixpkgs so HM-built packages keep their CUDA
      # acceleration from before the migration.
      nixpkgs.config.cudaSupport = true;

      # Monitor layout for this host's displays.
      xdg.configFile."niri/outputs.kdl".source = lib.mkForce ./niri-outputs.kdl;
    };
  };
}
