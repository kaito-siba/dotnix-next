{
  # cship: Claude Code statusLine renderer
  flake.modules.homeManager.claude-code =
    { pkgs, ... }:
    {
      home.packages = [ (pkgs.callPackage ./_package.nix { }) ];

      xdg.configFile."cship.toml".source = ./cship.toml;
    };
}
