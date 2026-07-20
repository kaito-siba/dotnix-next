{ config, ... }:
{
  # The application itself is a cask, declared in modules/homebrew.
  #
  # Hammerspoon looks for its config in ~/.hammerspoon unless told otherwise,
  # and the only way to tell it is this preference. It used to be written by a
  # `defaults write` on every login, which is a one-shot setting run on a hot
  # path; nix-darwin applies it once at activation instead.
  flake.modules.darwin.hammerspoon =
    let
      inherit (config.flake.meta.users.w963n) username;
    in
    {
      system.defaults.CustomUserPreferences."org.hammerspoon.Hammerspoon" = {
        MJConfigFile = "/Users/${username}/.config/hammerspoon/init.lua";
      };
    };
}
