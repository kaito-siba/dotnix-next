{
  flake.modules.homeManager.ghostty =
    { pkgs, lib, ... }:
    {
      programs.ghostty = {
        enable = true;

        # nixpkgs only source-builds ghostty for Linux; the macOS app is an
        # Xcode project, packaged from the official release as ghostty-bin.
        package = lib.mkIf pkgs.stdenv.isDarwin pkgs.ghostty-bin;
      };
    };
}
