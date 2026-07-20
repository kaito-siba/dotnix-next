{
  flake.modules.homeManager.gnupg =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        gnupg
        pinentry_mac
      ];

      # gpg-agent has no usable default pinentry on macOS, so a passphrase
      # prompt would fail rather than appear. home-manager's gpg-agent service
      # is systemd-only, hence the plain config file.
      home.file.".gnupg/gpg-agent.conf".text = ''
        pinentry-program ${pkgs.pinentry_mac}/bin/pinentry-mac
      '';
    };
}
