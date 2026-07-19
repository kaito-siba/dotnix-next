{
  flake.modules.homeManager.base = {
    programs.home-manager.enable = true;

    systemd.user.startServices = "sd-switch";

    services = {
      home-manager.autoExpire = {
        enable = true;
        frequency = "weekly";
        store.cleanup = true;
      };
    };
  };
}
