{
  # The fn (globe) key opens the system Emoji & Symbols picker. Ctrl+Cmd+Space
  # only works in apps whose Edit menu carries that item, which Ghostty and
  # some Electron apps do not; the globe key works everywhere.
  flake.modules.darwin.desktop = {
    system.defaults.hitoolbox.AppleFnUsageType = "Show Emoji & Symbols";
  };
}
