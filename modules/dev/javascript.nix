{
  flake.modules.homeManager."dev/javascript" =
    { pkgs, ... }:
    {
      # nodejs itself comes from dev/web to avoid two node versions colliding
      # in the profile.
      home.packages = with pkgs; [
        biome
      ];

      programs.yarn.enable = true;
    };
}
