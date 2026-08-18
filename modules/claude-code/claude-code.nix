{
  flake.modules.homeManager.claude-code = 
  { pkgs, inputs, ...}:
  {
    home.packages = [
      inputs.claude-code.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
  };
}
