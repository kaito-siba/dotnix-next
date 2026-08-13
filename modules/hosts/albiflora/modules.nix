{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos."hosts/albiflora" = {
    imports =
      with config.flake.modules.nixos;
      [
        base
        shell
        openssh
        virtualisation
        tailscale
        claude-code
        noctalia

        # Desktop session
        desktop
        bluetooth
        fonts
        xremap

        # Hardware
        nvidia
        coolercontrol

        # Compatibility for non-nix binaries (incl. mason-installed LSPs)
        compat

        # Users
        w963n
      ]
      ++ [
        {
          home-manager.users.w963n.imports = [
            hm.base
            hm.shell
            hm.cli-tools
            hm.neovim
            hm.obsidian
            hm.claude-code
            hm.ai
            hm.llama
            hm.rbw

            # hm.calendar is deliberately absent: modules/calendar/secrets is
            # encrypted for radiata and the mac only, so the user-level
            # sops-nix activation fails here. Re-add it once calendar.yaml has
            # been re-encrypted with this host's w963n age key, which is
            # already listed in .sops.yaml.

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
