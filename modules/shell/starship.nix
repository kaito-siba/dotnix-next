{
  # The config is a hand-tuned catppuccin theme. It stays TOML rather than being
  # translated into programs.starship.settings: transcribing 300+ lines of
  # format strings into Nix buys nothing and loses upstream diffability.
  flake.modules.homeManager.shell = {
    programs.starship.enable = true;

    xdg.configFile."starship.toml".source = ./starship.toml;
  };
}
