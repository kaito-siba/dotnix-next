{
  # Export the XDG base directories so tools that honour the spec keep their
  # state out of $HOME. Per-tool coaxing (for the ones that need an explicit
  # variable) belongs in that tool's own module, not here.
  flake.modules.homeManager.base = {
    xdg.enable = true;
  };
}
