{
  # Console greeter that launches the niri session through uwsm. The
  # auto-logged-in user is host specific and set in each host module.
  flake.modules.nixos.niri =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        tuigreet
      ];

      services.greetd = {
        enable = true;
        settings = rec {
          initial_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --asterisks --cmd 'uwsm start niri-uwsm.desktop'";
          };
          default_session = initial_session;
        };
      };
    };
}
