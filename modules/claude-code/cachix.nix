{
  # Binary cache for the claude-code input so hosts do not rebuild it.
  flake.modules.nixos.claude-code = {
    nix.settings = {
      substituters = [ "https://claude-code.cachix.org" ];
      trusted-public-keys = [
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      ];
    };
  };
}
