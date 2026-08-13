{
  inputs,
  lib,
  config,
  ...
}:
{
  # Modules that need packages ahead of the stable release take them from the
  # `pkgs-unstable` module argument. It is instantiated once per platform with
  # the same unfree predicate as the stable instance.
  flake.modules =
    let
      predicate = pkg: builtins.elem (lib.getName pkg) config.nixpkgs.allowedUnfreePackages;

      withUnstable =
        { pkgs, ... }:
        {
          _module.args.pkgs-unstable = import inputs.nixpkgs-unstable {
            system = pkgs.stdenv.hostPlatform.system;
            config.allowUnfreePredicate = predicate;
          };
        };
    in
    {
      nixos.base = withUnstable;
      homeManager.base = withUnstable;
    };
}
