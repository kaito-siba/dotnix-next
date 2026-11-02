{
  # Menu-bar daemon. The binary comes from nixpkgs and runs as a launchd
  # agent owned by home-manager; the config is executed at daemon startup.
  #
  # After changing the config, restart the agent:
  #   launchctl kickstart -k gui/$(id -u)/org.nix-community.home.sketchybar
  # Do NOT use `sketchybar --reload`: with the config symlinked into the
  # store it resets the bar to defaults and then silently fails to re-run
  # the config, leaving an empty bar.
  flake.modules.homeManager."desktop/darwin" =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      home.packages = [ pkgs.sketchybar ];

      xdg.configFile."sketchybar" = {
        source = ./config;
        recursive = true;
      };

      launchd.agents.sketchybar = {
        enable = true;
        config = {
          ProgramArguments = [ "${pkgs.sketchybar}/bin/sketchybar" ];
          RunAtLoad = true;
          KeepAlive = true;
          ProcessType = "Interactive";
          # The plugins shell out to tools from the user profile and, for the
          # Homebrew popup, to brew itself; launchd agents start with a bare
          # PATH otherwise.
          EnvironmentVariables.PATH = lib.concatStringsSep ":" [
            "${config.home.profileDirectory}/bin"
            "/run/current-system/sw/bin"
            "/opt/homebrew/bin"
            "/usr/bin"
            "/bin"
            "/usr/sbin"
            "/sbin"
          ];
          StandardOutPath = "${config.xdg.cacheHome}/sketchybar.log";
          StandardErrorPath = "${config.xdg.cacheHome}/sketchybar.log";
        };
      };
    };
}
