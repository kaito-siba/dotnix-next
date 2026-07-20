{
  # The photography workflow: raw development for the Fujifilm camera, a raw
  # editor and photo backup. rawtherapee's nixpkgs meta claims darwin support,
  # but its dependency chain pulls in libselinux and fails to evaluate, so all
  # three stay casks.
  flake.modules.darwin.photography = {
    homebrew.casks = [
      "amazon-photos"
      "fujifilm-x-raw-studio"
      "rawtherapee"
    ];
  };
}
