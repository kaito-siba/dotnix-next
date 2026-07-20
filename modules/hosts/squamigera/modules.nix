{ config, ... }:
{
  flake.modules.darwin."hosts/squamigera" = {
    imports =
      with config.flake.modules.darwin;
      [
        base
        shell

        # Users
        w963n
      ]
      ++ [
        {
          home-manager.users.w963n.imports = with config.flake.modules.homeManager; [
            base
          ];
        }
      ];
  };
}
