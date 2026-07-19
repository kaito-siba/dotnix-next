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

      homeManager.base = {
        home = {
          inherit stateVersion;
        };
      };
    };
}
