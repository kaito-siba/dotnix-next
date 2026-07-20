{ config, lib, ... }:
let
  serverPort = config.services.searx.serverPort;
in
{
  options.services.searx.serverPort = lib.mkOption {
    type = lib.types.int;
    default = 8888;
  };

  config.flake.modules.nixos.searxng =
    { config, pkgs, ... }:
    {
      sops.secrets."searxng-env" = {
        sopsFile = ./secrets/searxng.env;
        format = "dotenv";
      };

      services.searx = {
        enable = true;
        package = pkgs.searxng;
        environmentFile = config.sops.secrets."searxng-env".path;
        settings = {
          server = {
            port = serverPort;
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
