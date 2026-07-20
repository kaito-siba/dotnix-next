{
  # Fonts have no self-update story, so unlike the GUI casks there is nothing
  # a cask does better: nixpkgs versions land in /Library/Fonts/Nix Fonts.
  flake.modules.darwin.fonts =
    { pkgs, ... }:
    {
      fonts.packages = with pkgs; [
        nerd-fonts.fira-code
        nerd-fonts.hack
        nerd-fonts.meslo-lg
        nerd-fonts.symbols-only
      ];
    };
}
