{
  # Ships a system extension, so it stays a cask. Its config under
  # ~/.config/karabiner is written back by the app itself, so it is not
  # vendored here.
  flake.modules.darwin.desktop = {
    homebrew.casks = [ "karabiner-elements" ];
  };
}
