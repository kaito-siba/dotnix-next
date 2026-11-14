{
  # nh works on darwin since v4 (`nh darwin switch`), but nix-darwin has no
  # programs.nh module yet, so the pieces are assembled by hand: the package,
  # NH_FLAKE, a weekly `nh clean` daemon, and an alias that pins the flake attribute. The alias matters
  # on every darwin host here -- hostname-based resolution never actually
  # worked: incarnata's hostname is managed outside the repo, and squamigera's
  # LocalHostName is capitalized while the attribute is not.
  flake.modules.darwin.base =
    {
      pkgs,
      config,
      hostConfig,
      ...
    }:
    {
      environment.systemPackages = [ pkgs.nh ];

      # The flake checkout lives at the ghq-style path under the primary
      # user's home on every machine.
      environment.variables.NH_FLAKE =
        "/Users/${config.system.primaryUser}/repos/hobby/github.com/kaito-siba/dotnix-next";

      environment.shellAliases.nhs = "nh darwin switch -H ${hostConfig.name}";

      # Counterpart of programs.nh.clean on NixOS (same retention, see
      # nix.nix). Without it nothing ever deletes old generations on darwin:
      # optimise.automatic only deduplicates. nix.gc is not used because it
      # only collects root's and the system profiles, leaving home-manager
      # generations under ~/.local/state behind; `nh clean all` walks every
      # user's profiles too. launchd runs a missed calendar slot on wake.
      launchd.daemons.nh-clean = {
        path = [ config.nix.package ];
        command = "${pkgs.nh}/bin/nh clean all --keep-since 14d --keep 5";
        serviceConfig = {
          RunAtLoad = false;
          StartCalendarInterval = [
            {
              Weekday = 0;
              Hour = 3;
              Minute = 15;
            }
          ];
          StandardOutPath = "/var/log/nh-clean.log";
          StandardErrorPath = "/var/log/nh-clean.log";
        };
      };
    };
}
