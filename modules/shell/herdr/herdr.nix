{
  flake.modules.homeManager.shell =
    { pkgs, inputs, ... }:
    {
      home.packages = [ inputs.herdr.packages.${pkgs.system}.default ];

      xdg.configFile."herdr/config.toml".source = ./config.toml;
    };
}
