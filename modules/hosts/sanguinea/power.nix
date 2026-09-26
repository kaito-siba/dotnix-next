{
  # Laptop power management: battery state for noctalia and power profiles.
  flake.modules.nixos."hosts/sanguinea" = {
    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;
  };
}
