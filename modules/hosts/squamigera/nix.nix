{
  flake.modules.darwin."hosts/squamigera" =
    { lib, ... }:
    {
      # TRANSITIONAL: this host still runs Determinate Nix, which manages
      # /etc/nix/nix.conf and the daemon itself. nix-darwin refuses to activate
      # unless it is told to keep its hands off, and store optimisation asserts
      # on nix.enable, so base's setting has to be forced back off here.
      #
      # Remove this whole module once Determinate Nix has been uninstalled and
      # Nix is handed over to nix-darwin; base already carries what we want.
      nix.enable = false;
      nix.optimise.automatic = lib.mkForce false;
    };
}
