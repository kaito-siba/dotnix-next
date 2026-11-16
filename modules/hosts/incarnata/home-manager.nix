{
  flake.modules.darwin."hosts/incarnata" = {
    # This host's dotfiles were chezmoi-managed (kaito-siba/dotfiles) until
    # now, so activation would otherwise abort on the existing zsh, git, nvim
    # and friends that home-manager replaces. Keep the originals next to the
    # generated ones rather than losing them.
    home-manager.backupFileExtension = "before-nix";

    # Slack の依頼と standup の下書きは albiflora が作る (modules/work-digest)。
    # herdr-app の Inbox から tailnet 越しに読む。
    home-manager.users.k-nanchi.herdr-app.workDigestUrl = "http://albiflora:8792";
  };
}
