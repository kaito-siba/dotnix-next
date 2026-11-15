{ inputs, ... }:
{
  flake.modules.nixos.qnetd = {
    imports = [ "${inputs.herbarium}/nixos/modules/qnetd.nix" ];
    services.corosync-qnetd = {
      enable = true;
      openFirewall = true;
      allowedSources = [ "10.9.63.0/24" ];
    };
  };
}
