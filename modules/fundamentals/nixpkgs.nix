{ config, lib, inputs, ... }:
{
  perSystem =
    { system, ... }:
    let
      predicate = pkg: builtins.elem (lib.getName pkg) config.nixpkgs.allowedUnfreePackages;
    in
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;

	      config.allowUnfreePredicate = predicate;

	      overlays = [
          inputs.nix-openclaw.overlays.default
        ];
      };
    };
}
