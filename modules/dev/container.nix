{
  # Container tooling. On darwin the daemon runs in a lima VM made from the
  # stock docker template (`limactl start template://docker`) and the docker
  # CLI talks to the socket that VM forwards to the host -- DOCKER_HOST below
  # assumes the template's default instance name "docker". Compose and buildx
  # are linked in as CLI plugins so `docker compose` / `docker buildx`
  # resolve. Linux hosts get their daemon from the system virtualisation
  # module instead, so everything here is darwin-only.
  flake.modules.homeManager.dev =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      home.packages = with pkgs; [
        lima
        docker-client
        docker-credential-helpers
      ];

      home.sessionVariables.DOCKER_HOST =
        "unix://${config.home.homeDirectory}/.lima/docker/sock/docker.sock";

      home.file = {
        ".docker/cli-plugins/docker-compose".source = "${pkgs.docker-compose}/bin/docker-compose";
        ".docker/cli-plugins/docker-buildx".source = "${pkgs.docker-buildx}/bin/docker-buildx";
      };
    };
}
