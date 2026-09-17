{
  inputs,
  lib,
  config,
  ...
}:
let
  allowedUnfree = config.nixpkgs.allowedUnfreePackages;

  # cudaSupport = true の llama-cpp は公開 binary cache に存在しない
  # (cache.nixos.org は unfree な CUDA redist をビルドせず、
  # cuda-maintainers.cachix.org は現在アクセス不可) ので必ずローカルビルドに
  # なる。nixpkgs の既定では 7.5〜12.1 の 9 アーキテクチャ分 ggml-cuda を
  # コンパイルするため、ホストの GPU の compute capability だけに絞る。
  llama-cpp =
    system: capabilities:
    (import inputs.nixpkgs-llama {
      inherit system;
      config = {
        allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowedUnfree;
        cudaCapabilities = capabilities;
      };
    }).llama-cpp.override
      { cudaSupport = true; };
in
{
  # Local LLM inference with CUDA offload; chat templates for the models in
  # use live under ./config.
  flake.modules.homeManager.llama =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      options.llama.cudaCapabilities = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        example = [ "12.0" ];
        description = ''
          ビルド対象にする GPU の compute capability。CUDA ツールキットの
          バージョンではない点に注意 (RTX 4090 = 8.9, RTX 5090 = 12.0)。
          既定値を置かずホスト側での明示を必須にしている。
        '';
      };

      config = {
        home.packages = [
          (llama-cpp pkgs.stdenv.hostPlatform.system config.llama.cudaCapabilities)
        ];

        xdg.configFile."llama" = {
          source = ./config;
          recursive = true;
        };
      };
    };
}
