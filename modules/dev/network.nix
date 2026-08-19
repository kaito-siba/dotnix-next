{
  # Network debugging: intercepting proxy, tunnels and packet capture.
  flake.modules = {
    homeManager.dev =
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          cloudflared
          mitmproxy
        ];
      };

    # Wireshark stays a cask: capturing needs the ChmodBPF launch daemon whose
    # installer ships inside the app bundle, which the nixpkgs build cannot
    # set up.
    darwin.dev.homebrew.casks = [ "wireshark-app" ];
  };
}
