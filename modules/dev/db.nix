{
  # Database client CLIs (servers run elsewhere; these are for poking at them).
  flake.modules = {
    homeManager.dev =
      { pkgs, lib, ... }:
      {
        home.packages =
          with pkgs;
          [
            postgresql
            mysql84
            lazysql
          ]
          # mysql-shell comes from homebrew on darwin -- see the other half below.
          ++ lib.optionals stdenv.hostPlatform.isLinux [ mysql-shell ];

        programs.zsh.shellAliases = {
          lq = "lazysql";
        };
      };

    # nixpkgs' mysql-shell has no aarch64-darwin binary cache because it does
    # not build there: it compiles with -Werror and clang rejects
    # metadata_storage.cc:1905, where a literal 0 is passed as the const char*
    # argument of get_string() (-Wnonnull). gcc-built Linux is unaffected, so
    # only the Mac would grind through an hour of source build and then fail.
    # Hence the exception to "terminal tools come from nix" -- and a cask
    # rather than a brew, because homebrew has no mysql-shell formula, only
    # Oracle's signed .pkg. It symlinks itself onto /usr/local/bin.
    darwin.dev.homebrew.casks = [ "mysql-shell" ];
  };
}
