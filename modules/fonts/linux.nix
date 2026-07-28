{
  # Linux side of the fonts concern; the darwin flavour lives in fonts.nix.
  #
  # The private Guguru Sans Code TTFs from the previous repo (~148MB of
  # binaries) are deliberately not vendored here. Install them out of band or
  # move them into a private flake input if they are still wanted.
  flake.modules.nixos.fonts =
    { pkgs, ... }:
    {
      fonts = {
        fontDir.enable = true;
        packages = [
          pkgs.noto-fonts
          pkgs.noto-fonts-cjk-sans
          pkgs.noto-fonts-color-emoji
          pkgs.dejavu_fonts
          pkgs.nerd-fonts.jetbrains-mono
          pkgs.maple-mono.NF-CN
          pkgs.source-han-sans
          pkgs.source-han-serif
          pkgs.ibm-plex
        ];

        enableDefaultPackages = false;

        fontconfig.defaultFonts = {
          serif = [
            "Noto Serif"
            "Noto Color Emoji"
          ];
          sansSerif = [
            "Noto Sans CJK JP"
            "Noto Sans"
            "Noto Color Emoji"
          ];
          monospace = [
            "Noto Sans Mono"
            "Noto Color Emoji"
            "Dejavu Sans Mono"
          ];
          emoji = [ "Noto Color Emoji" ];
        };

        # https://wiki.nixos.org/wiki/Fonts
        # Noto Color Emoji doesn't render on Firefox
        fontconfig.useEmbeddedBitmaps = true;
      };
    };
}
