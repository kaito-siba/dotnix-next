{
  # Xbox One wireless controllers over bluetooth.
  # https://www.reddit.com/r/NixOS/comments/1hdsfz0/what_do_i_have_to_do_to_make_my_xbox_controller/
  flake.modules.nixos.gaming =
    { config, ... }:
    {
      hardware.xpadneo.enable = true;

      boot = {
        extraModulePackages = with config.boot.kernelPackages; [ xpadneo ];
        extraModprobeConfig = ''
          options bluetooth disable_ertm=Y
        '';
      };
    };
}
