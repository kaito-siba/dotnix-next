{
  flake.modules.nixos.searxng =
    { config, pkgs, ... }:
    {
      sops.secrets."searxng-env" = {
        sopsFile = ./secrets/searxng.env;
        format = "dotenv";
      };

      networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8888 ];

      services.searx = {
        enable = true;
        package = pkgs.searxng;
        environmentFile = config.sops.secrets."searxng-env".path;
        settings = {
          server = {
            port = 8888;
            bind_address = "0.0.0.0";
            secret_key = "@SEARXING_SECRET_KEY@";
          };
          engines = [
            {
              name = "ahmia";
              inactive = true;
            }
            {
              name = "torch";
              inactive = true;
            }
            {
              name = "radio browser";
              inactive = true;
            }
            {
              name = "wikidata";
              inactive = true;
            }
          ];
          search.formats = [
            "html"
            "json"
          ];
        };
      };
    };
}
