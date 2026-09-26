{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos."hosts/sanguinea" = {
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
        printing
        xremap

        # Compatibility for non-nix binaries (incl. mason-installed LSPs)
        compat

        # Storage
        nas

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
            hm.rbw

            # hm.calendar is deliberately absent: modules/calendar/secrets is
            # not encrypted for this host's w963n age key yet, so the
            # user-level sops-nix activation would fail. Re-add it once the key
            # is listed in .sops.yaml and calendar.yaml has been re-encrypted.

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
