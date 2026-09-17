{
  flake.modules.nixos."hosts/albiflora" = {
    imports = [ ./_hwconf.nix ];

    # RTX 5090 (Blackwell). NVIDIA's proprietary kernel modules never gained
    # support for this generation, so the open modules are the only ones that
    # bring the card up at all -- hence the override of the shared default.
    hardware.nvidia.open = true;

    # RTX 5090 (GB202) の compute capability。llama-cpp の CUDA ビルドを
    # このアーキテクチャだけに絞る。
    home-manager.users.w963n.llama.cudaCapabilities = [ "12.0" ];
  };
}
