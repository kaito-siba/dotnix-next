{
  # Local LLM inference with CUDA offload; chat templates for the models in
  # use live under ./config.
  flake.modules.homeManager.llama =
    { pkgs-unstable, ... }:
    {
      home.packages = [
        (pkgs-unstable.llama-cpp.override {
          cudaSupport = true;
        })
      ];

      xdg.configFile."llama" = {
        source = ./config;
        recursive = true;
      };
    };
}
