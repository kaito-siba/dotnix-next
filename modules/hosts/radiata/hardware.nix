{
  flake.modules.nixos."hosts/radiata" = {
    imports = [ ./_hwconf.nix ];
  };
}
