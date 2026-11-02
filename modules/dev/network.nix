{
  # Network debugging: intercepting proxy and tunnels. Wireshark is not
  # installed: capturing on darwin needs the ChmodBPF launch daemon that only
  # the app bundle's installer sets up, so it would have to stay a cask, and
  # it was not in use. Install it by hand when needed.
  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        cloudflared
        mitmproxy
      ];
    };
}
