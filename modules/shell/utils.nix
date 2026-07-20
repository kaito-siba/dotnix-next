{
  # Single-binary tools with nothing to configure. They share a file because
  # splitting them would produce modules that differ only in a package name.
  # Anything that grows real configuration should move out into its own module.
  flake.modules.homeManager.shell =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        cmake
        coreutils
        glow
        ncdu
        tree
        wakeonlan
        wget
      ];
    };
}
