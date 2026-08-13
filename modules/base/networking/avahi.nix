{
  # mDNS resolution so *.local names (printers, other machines on the LAN)
  # work without a DNS server. nssmdns4 wires it into nsswitch; openFirewall
  # opens 5353/udp, which is also the module default.
  flake.modules.nixos.base = {
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
  };
}
