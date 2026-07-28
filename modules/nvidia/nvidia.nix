{
  nixpkgs.allowedUnfreePackages = [
    "nvidia-x11"
    "nvidia-kernel-modules"
    "nvidia-userspace"
    "nvidia-settings"
    "nvidia-persistenced"
    # CUDA-enabled builds (cudaSupport / llama-cpp) pull individual redist
    # packages, each with its own pname.
    "cuda-merged"
    "cudatoolkit"
    "cuda_cudart"
    "cuda_cccl"
    "cuda_nvcc"
    "cuda_cuobjdump"
    "cuda_cupti"
    "cuda_cuxxfilt"
    "cuda_gdb"
    "cuda_nvdisasm"
    "cuda_nvml_dev"
    "cuda_nvprune"
    "cuda_nvrtc"
    "cuda_nvtx"
    "cuda_profiler_api"
    "cuda_sanitizer_api"
    "libcublas"
    "libcufft"
    "libcurand"
    "libcusolver"
    "libcusparse"
    "libnvjitlink"
    "libnpp"
    "cudnn"
  ];

  flake.modules.nixos.nvidia =
    { pkgs, ... }:
    {
      # hardware.nvidia only loads the driver when xserver declares it, even
      # for a pure wayland session.
      services.xserver = {
        enable = true;
        videoDrivers = [
          "nvidia"
          "intel"
        ];
      };

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          vulkan-loader
          libva-vdpau-driver
          libvdpau-va-gl
          nvidia-vaapi-driver
        ];
        extraPackages32 = with pkgs; [ vulkan-loader ];
      };

      hardware.nvidia = {
        modesetting.enable = true;
        open = false;
        nvidiaSettings = true;
        powerManagement.enable = true;
      };

      hardware.nvidia-container-toolkit.enable = true;

      nixpkgs.config.cudaSupport = true;

      boot.extraModprobeConfig = ''
        options nvidia-drm modeset=1 fbdev=0
      '';

      environment.systemPackages = with pkgs; [
        cudatoolkit
        nvtopPackages.full
      ];
    };
}
