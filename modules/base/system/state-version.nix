{
  flake.modules =
    let
      stateVersion = "25.11";
    in
    {
      nixos.base = {
        system = {
          inherit stateVersion;
        };
      };

      # nix-darwin tracks its own integer state version, unrelated to the
      # nixpkgs release string used by NixOS and home-manager.
      darwin.base = {
        system.stateVersion = 6;
      };

      homeManager.base = {
        home = {
          inherit stateVersion;
        };
      };
    };
}
