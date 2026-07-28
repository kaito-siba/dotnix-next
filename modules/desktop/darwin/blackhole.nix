{
  # Virtual audio driver, so it stays a cask.
  flake.modules.darwin.desktop = {
    homebrew.casks = [ "blackhole-16ch" ];
  };
}
