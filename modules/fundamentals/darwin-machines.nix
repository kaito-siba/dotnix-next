{ inputs, lib, config, ... }:
let
  prefix = "hosts/";
in
{
  flake.darwinConfigurations = lib.pipe (config.flake.modules.darwin or { }) [
    (lib.filterAttrs (name: _: lib.hasPrefix prefix name))
    (lib.mapAttrs' (name: module:
      let
        hostName = lib.removePrefix prefix name;
        specialArgs = {
          inherit inputs;
          hostConfig = {
            name = hostName;
          };
        };
      in
      lib.nameValuePair hostName (inputs.nix-darwin.lib.darwinSystem {
        inherit specialArgs;
        modules = [
          module
          inputs.home-manager.darwinModules.home-manager
          {
            home-manager.extraSpecialArgs = specialArgs;
          }
        ];
      })
    ))
  ];
}
