{
  # workaround: onlyoffice desktop app needs some fonts to work, but it doesn't
  # use the system fonts, so copy them to the user's home directory and update
  # the font cache:
  #   mkdir -p ~/.local/share/fonts
  #   cp -L /run/current-system/sw/share/X11/fonts/* ~/.local/share/fonts/
  #   fc-cache -fv
  flake.modules.homeManager.onlyoffice = {
    programs.onlyoffice.enable = true;
  };
}
