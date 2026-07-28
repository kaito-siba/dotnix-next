{
  # Google Calendar sync (vdirsyncer) + TUI client (khal). OAuth secrets are
  # age-encrypted in the private nix-secrets repo and decrypted by ragenix.
  flake.modules.homeManager.calendar =
    { inputs, config, ... }:
    {
      imports = [
        inputs.ragenix.homeManagerModules.default
      ];

      accounts.calendar = {
        basePath = ".calendar";
        accounts.main = {
          name = "main";
          remote = {
            type = "google_calendar";
          };
          khal = {
            enable = true;
            addresses = [
              "r.k.v.1225kaito@gmail.com"
            ];
            type = "discover";
          };
          vdirsyncer = {
            enable = true;
            clientIdCommand = [
              "cat"
              "${config.home.homeDirectory}/.secrets/calendar/oauth_client_id"
            ];
            clientSecretCommand = [
              "cat"
              "${config.home.homeDirectory}/.secrets/calendar/oauth_client_secret"
            ];
            tokenFile = "${config.xdg.dataHome}/vdirsyncer/google-calendar-token";
            collections = [
              "from a"
              "from b"
            ];
            metadata = [
              "color"
              "displayname"
            ];
          };
        };
      };

      programs.khal = {
        enable = true;
        locale = {
          timeformat = "%H:%M";
          dateformat = "%Y-%m-%d";
          longdateformat = "%Y-%m-%d";
          datetimeformat = "%Y-%m-%d %H:%M";
          longdatetimeformat = "%Y-%m-%d %H:%M";
        };
      };

      programs.vdirsyncer = {
        enable = true;
      };

      services.vdirsyncer = {
        enable = true;
      };

      age.secrets = {
        "calendar-oauth-client-id" = {
          file = "${inputs.mysecrets}/calendar/oauth_client_id.age";
          path = "${config.home.homeDirectory}/.secrets/calendar/oauth_client_id";
        };
        "calendar-oauth-client-secret" = {
          file = "${inputs.mysecrets}/calendar/oauth_client_secret.age";
          path = "${config.home.homeDirectory}/.secrets/calendar/oauth_client_secret";
        };
      };
    };
}
