{
  # One "watch videos" concern, platform-flavored: IINA is the native macOS
  # frontend built on mpv, so darwin gets it instead of bare mpv.
  flake.modules.homeManager.video-player =
    { pkgs, lib, ... }:
    lib.mkMerge [
      (lib.mkIf pkgs.stdenv.isDarwin {
        home.packages = [ pkgs.iina ];
      })
      (lib.mkIf pkgs.stdenv.isLinux {
        programs.mpv.enable = true;
      })
    ];
}
