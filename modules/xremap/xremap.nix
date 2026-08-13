{
  # Key remapping daemon. Device specific modmaps live in each host module.
  flake.modules.nixos.xremap =
    { inputs, ... }:
    {
      imports = [ inputs.xremap.nixosModules.default ];

      services.xremap = {
        enable = true;
        withNiri = true;
      };
    };
}
