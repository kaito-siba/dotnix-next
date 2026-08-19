{
  # nh works on darwin since v4 (`nh darwin switch`), but nix-darwin has no
  # programs.nh module yet, so the pieces are assembled by hand: the package,
  # NH_FLAKE, and an alias that pins the flake attribute. The alias matters
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
    };
}
