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
        claude-code

        # Desktop session
        desktop
        bluetooth
        fonts
        printing
        xremap

        # Hardware
        nvidia
        coolercontrol
        gaming

        # Compatibility for non-nix binaries (incl. mason-installed LSPs)
        compat

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
            hm.calendar
            hm.rbw

            # Terminal
            hm.ghostty

            # Desktop session
            hm."desktop/linux"
            hm.noctalia

            # Desktop applications
            hm.zen-browser
            hm.chromium
            hm.slack
            hm.mail
            hm.vesktop
            hm.vscode
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
