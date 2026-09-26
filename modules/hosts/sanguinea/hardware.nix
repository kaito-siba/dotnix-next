{
  flake.modules.nixos."hosts/sanguinea" = {
    imports = [ ./_hwconf.nix ];

    # AMD APU (integrated graphics only); no dGPU module needed.
    hardware.graphics.enable = true;
  };
}
