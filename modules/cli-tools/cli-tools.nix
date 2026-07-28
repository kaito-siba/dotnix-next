{
  # CLI tooling carried over from the previous radiata home profile. Kept as
  # its own module (rather than folded into shell/utils) so hosts opt in and
  # platform support only needs to hold where it is actually used.
  flake.modules.homeManager.cli-tools =
    { pkgs, pkgs-unstable, ... }:
    {
      home.packages =
        (with pkgs; [
          # archives
          zip
          xz
          unzip
          p7zip

          # utils
          yq-go
          visidata
          ffmpeg
          fastfetch
          with-shell
          lnav
        ])
        ++ (with pkgs-unstable; [
          devenv
          keifu
        ]);
    };
}
