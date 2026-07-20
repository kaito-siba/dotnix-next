{ config, ... }:
{
  # Hammerspoon looks for its config in ~/.hammerspoon unless told otherwise,
  # and the only way to tell it is this preference. It used to be written by a
  # `defaults write` on every login, which is a one-shot setting run on a hot
  # path; nix-darwin applies it once at activation instead.
  #
  # No init.lua exists yet -- the app currently runs with an empty config.
  # When one is written it belongs next to this file, vendored the way the
  # aerospace and sketchybar configs are.
  flake.modules.darwin.desktop =
    let
      inherit (config.flake.meta.users.w963n) username;
    in
    {
      homebrew.casks = [ "hammerspoon" ];

      system.defaults.CustomUserPreferences."org.hammerspoon.Hammerspoon" = {
        MJConfigFile = "/Users/${username}/.config/hammerspoon/init.lua";
      };
    };
}
