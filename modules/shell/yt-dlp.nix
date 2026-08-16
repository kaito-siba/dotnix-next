{
  flake.modules.homeManager.shell =
    { pkgs-unstable, ... }:
    {
      programs.yt-dlp = {
        enable = true;
        package = pkgs-unstable.yt-dlp;
      };
    };
}
