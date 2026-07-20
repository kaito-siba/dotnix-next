{
  flake.modules.darwin."hosts/squamigera" = {
    # This host predates nix owning its dotfiles, so activation would otherwise
    # abort on the hand-written zsh, git, nvim and tmux configs it is replacing.
    # Keep the originals next to the generated ones rather than losing them.
    home-manager.backupFileExtension = "before-nix";
  };
}
