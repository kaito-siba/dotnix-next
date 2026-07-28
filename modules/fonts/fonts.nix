{
  # One font set shared across platforms, plus platform extras. On darwin the
  # nixpkgs packages land in /Library/Fonts/Nix Fonts; on Linux fontconfig is
  # configured below.
  flake.modules =
    let
      sharedFonts =
        pkgs: with pkgs; [
          maple-mono.NF-CN # terminal font (ghostty ほか)
          ibm-plex # IBM Plex Sans JP (noctalia UI)
          nerd-fonts.jetbrains-mono
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
        ];
    in
    {
      darwin.fonts =
        { pkgs, ... }:
        {
          fonts.packages =
            sharedFonts pkgs
            ++ (with pkgs; [
              nerd-fonts.fira-code
              nerd-fonts.hack
              nerd-fonts.meslo-lg
              nerd-fonts.symbols-only
            ]);
        };

      nixos.fonts =
        { pkgs, ... }:
        {
          fonts = {
            fontDir.enable = true;
            packages =
              sharedFonts pkgs
              ++ (with pkgs; [
                dejavu_fonts
                source-han-sans
                source-han-serif
              ]);

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
    };
}
