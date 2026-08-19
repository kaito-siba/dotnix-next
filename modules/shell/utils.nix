{
  # Single-binary tools with nothing to configure. They share a file because
  # splitting them would produce modules that differ only in a package name.
  # Anything that grows real configuration should move out into its own module.
  flake.modules.homeManager.shell =
    { pkgs, lib, ... }:
    {
      home.packages =
        (with pkgs; [
          _7zz # 7-Zip, the maintained upstream (7zz)
          chafa
          cmake
          coreutils
          glow
          lnav
          ncdu
          pv
          tree
          vhs
          wakeonlan
          wget
        ])
        # NixOS already ships GNU sed as the system sed; only darwin needs it
        # on PATH to shadow the BSD one.
        ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.gnused ];
    };
}
