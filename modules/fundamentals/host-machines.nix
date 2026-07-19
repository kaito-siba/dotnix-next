{ inputs, lib, config, ... }:
let
  prefix = "hosts/";
in
{
  flake.nixosConfigurations = lib.pipe config.flake.modules.nixos [
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
      lib.nameValuePair hostName (inputs.nixpkgs.lib.nixosSystem {
        inherit specialArgs;
        modules = [ 
	  module
	  inputs.home-manager.nixosModules.home-manager
	  {
	    home-manager.extraSpecialArgs = specialArgs;
	  }
	];
      })
    ))
  ];
}
