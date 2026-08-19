{
  flake.modules.darwin."hosts/incarnata" = {
    # This host's dotfiles were chezmoi-managed (kaito-siba/dotfiles) until
    # now, so activation would otherwise abort on the existing zsh, git, nvim
    # and friends that home-manager replaces. Keep the originals next to the
    # generated ones rather than losing them.
    home-manager.backupFileExtension = "before-nix";
  };
}
