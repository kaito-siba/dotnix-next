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
        niri
        audio
        bluetooth
        ime
        fonts
        nautilus
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
            hm.lazysql
            hm.obsidian
            hm.claude-code
            hm.ai
            hm.sqlit
            hm.llama
            hm.aws
            hm.calendar
            hm.rbw

            # Terminal
            hm.ghostty

            # Desktop session
            hm.niri
            hm.noctalia
            hm.wayland
            hm.screenshot
            hm.theming
            hm.mozc
            hm.nautilus

            # Desktop applications
            hm.desktop-apps
            hm.zen-browser
            hm.vesktop
            hm.vscode
            hm.obs
            hm.onlyoffice
            hm.smoothcsv
            hm.mpv

            # Tracking
            hm.activitywatch

            # Development
            hm."dev/common"
            hm."dev/nix"
            hm."dev/python"
            hm."dev/web"
            hm."dev/rustup"
            hm."dev/javascript"
            hm."dev/php"
            hm."dev/db"
          ];
        }
      ];
  };
}
