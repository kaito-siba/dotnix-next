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
            # Brave Search API (キー認証)。スクレイパー系がIPブロックされたための根本対策
            # 無料枠: 2,000クエリ/月・1qps
            {
              name = "brave api";
              engine = "json_engine";
              shortcut = "bapi";
              categories = [
                "general"
                "web"
              ];
              search_url = "https://api.search.brave.com/res/v1/web/search?q={query}&count=20";
              method = "GET";
              headers = {
                Accept = "application/json";
                # searx-initはenvsubstで置換するため $VAR 形式 (environmentFile由来)
                "X-Subscription-Token" = "$BRAVE_API_KEY";
              };
              results_query = "web/results";
              url_query = "url";
              title_query = "title";
              content_query = "description";
              timeout = 5.0;
              disabled = false;
            }
            # 以下スクレイパー系はbot判定でブロック中(brave=rate limit, DDG/startpage=CAPTCHA)のため停止
            {
              name = "brave";
              disabled = true;
            }
            {
              name = "duckduckgo";
              disabled = true;
            }
            {
              name = "startpage";
              disabled = true;
            }
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
