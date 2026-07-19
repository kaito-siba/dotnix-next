{
  flake.modules.nixos.base = {
    services.xserver.xkb = {
      layout = "us";
      variant = "";
    };
  };
}
