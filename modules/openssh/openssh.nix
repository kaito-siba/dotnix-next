{
  flake.modules.nixos.openssh = {
    services.openssh = {
      enable = true;
      openFirewall = true;
      ports = [ 5831 ];
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        X11Forwarding = false;
      };
    };
  };
}
