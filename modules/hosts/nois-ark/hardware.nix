{
  flake.modules.nixos."hosts/nois-ark" = {
    imports = [ ./_hwconf.nix ];
  };
}
