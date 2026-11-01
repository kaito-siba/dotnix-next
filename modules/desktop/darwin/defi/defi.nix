{
  # Defi (https://github.com/qeude/Defi): a niri-style scrolling window
  # manager, on trial as the replacement for OmniWM. Alpha, macOS 26+ and
  # Apple Silicon only.
  #
  # Installed from the upstream release zip rather than the qeude/tap cask,
  # pinned to one version: bump `version` and `hash` together. The bundle is
  # self-signed ("Defi Release", no team) and not notarized, but fetchurl
  # never sets the quarantine attribute, so Gatekeeper does not get in the
  # way. Its designated requirement is the bundle id plus that certificate,
  # not the path, so the Accessibility / Screen Recording grants survive the
  # store path changing on a bump.
  #
  # The daemon runs from a launchd agent declared here instead of the app's
  # own "Launch at Login" (`defi service enable`), which would write an agent
  # pointing at whatever store path was current and go stale on the next
  # bump. Leave that menu item off.
  #
  # config.toml lists overrides only -- everything else is Defi's built-in
  # default (see CONFIGURATION.md upstream). The app live-reloads it on save.
  # The Settings window also writes to it: a GUI edit replaces the symlink and
  # is rolled back at the next switch (backed up as .before-nix), so changes
  # flow through this file.
  #
  # No host-specific state is needed: Defi follows the display arrangement set
  # in System Settings, so OmniWM's per-host routing overrides have no
  # counterpart here.
  flake.modules.homeManager."desktop/darwin" =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      version = "0.6.0";
      log = "${config.home.homeDirectory}/Library/Logs/Defi.log";

      defi = pkgs.stdenvNoCC.mkDerivation {
        pname = "defi";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://github.com/qeude/Defi/releases/download/v${version}/Defi-v${version}.zip";
          hash = "sha256-vh3BlqbEC80uvSbqPh7u9p6iIA4YVoZVAK3/UHDiQfM=";
        };

        nativeBuildInputs = [ pkgs.unzip ];
        sourceRoot = ".";
        dontConfigure = true;
        dontBuild = true;
        # The bundle is signed; the default fixup would strip the binaries and
        # break the signature.
        dontFixup = true;

        # The CLI finds defi-daemon next to its own path, so bin/defi execs it
        # in place rather than being a symlink.
        installPhase = ''
          mkdir -p $out/Applications $out/bin
          cp -R Defi.app $out/Applications/
          cat > $out/bin/defi <<SH
          #!/bin/sh
          exec "$out/Applications/Defi.app/Contents/MacOS/defi" "\$@"
          SH
          chmod +x $out/bin/defi
        '';

        meta.platforms = [ "aarch64-darwin" ];
      };
    in
    lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      home.packages = [ defi ];

      xdg.configFile."defi/config.toml".source = ./config/config.toml;

      launchd.agents.defi = {
        enable = true;
        config = {
          ProgramArguments = [ "${defi}/Applications/Defi.app/Contents/MacOS/defi-daemon" ];
          RunAtLoad = true;
          # Restart after a crash, but stay down after Quit from the menu.
          KeepAlive.SuccessfulExit = false;
          ProcessType = "Interactive";
          StandardOutPath = log;
          StandardErrorPath = log;
        };
      };
    };
}
