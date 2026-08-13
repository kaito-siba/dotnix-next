{
  flake.modules.nixos."hosts/albiflora" = {
    imports = [ ./_hwconf.nix ];

    # RTX 5090 (Blackwell). NVIDIA's proprietary kernel modules never gained
    # support for this generation, so the open modules are the only ones that
    # bring the card up at all -- hence the override of the shared default.
    hardware.nvidia.open = true;
  };
}
