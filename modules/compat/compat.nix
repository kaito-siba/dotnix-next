{
  # Make non-nix binaries and tools that expect FHS paths work.
  flake.modules.nixos.compat =
    { pkgs, ... }:
    {
      # https://github.com/tomrijndorp/vscode-finditfaster/issues/44
      services.envfs.enable = true;

      programs.nix-ld.enable = true;
      programs.nix-ld.libraries = with pkgs; [
        stdenv.cc.cc.lib # glibc, libstdc++ など
        zlib
        openssl
      ];
    };
}
