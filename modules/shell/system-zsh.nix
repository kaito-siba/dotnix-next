{
  # Zsh completions for packages installed via environment.systemPackages.
  flake.modules.nixos.shell = {
    environment.pathsToLink = [
      "/share/zsh"
    ];
  };
}
