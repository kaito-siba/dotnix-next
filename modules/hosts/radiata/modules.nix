{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos."hosts/radiata" = {
    imports =
      with config.flake.modules.nixos;
      [
        base
        shell
        openssh
        virtualisation
        tailscale
        noctalia

        # Desktop session
        desktop
        bluetooth
        fonts
        printing
        xremap
        fievel

        # Hardware
        nvidia
        coolercontrol
        gaming

        # Compatibility for non-nix binaries (incl. mason-installed LSPs)
        compat

        # Storage
        nas

        # Users
        rkv12
      ]
      ++ [
        {
          home-manager.users.rkv12.imports = [
            hm.base
            hm.shell
            hm.cli-tools
            hm.neovim
            hm.obsidian
            hm.claude-code
            hm.ai
            hm.llama

            # Terminal
            hm.ghostty

            # Desktop session
            hm."desktop/linux"
            hm.noctalia
            hm.fievel

            # Desktop applications
            hm.chromium
            hm.slack
            hm.vesktop
            hm.obs
            hm.onlyoffice
            hm.smoothcsv
            hm.video-player

            # Tracking
            hm.activitywatch

            # Development
            hm.dev
          ];
        }
      ];
  };
}
