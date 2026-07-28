{
  # Self-hosted game streaming host for Moonlight clients.
  flake.modules.nixos.gaming = {
    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
    };
  };
}
