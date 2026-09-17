{
  flake.modules.nixos."hosts/radiata" = {
    imports = [ ./_hwconf.nix ];

    # RTX 4090 (AD102) の compute capability。llama-cpp の CUDA ビルドを
    # このアーキテクチャだけに絞る。
    home-manager.users.rkv12.llama.cudaCapabilities = [ "8.9" ];
  };
}
