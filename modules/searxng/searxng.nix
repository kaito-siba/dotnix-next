{
  flake.modules.nixos.searxng =
    { config, pkgs, ... }:
    {
      # Provide the secret_key via sops instead of the Nix store (which is
      # world-readable). The `searxng` value is stored as a full env line
      # (SEARX_SECRET_KEY=...), so the decrypted secret file is itself a valid
      # environmentFile; the searx module substitutes the @VAR@ placeholder in
      # settings from it at service start.
      sops.secrets."searxng" = { };

      # tailnet の他ホストから wain:8888 で叩けるように、tailscale0 経由でのみ
      # 8888 を開放する（LAN/WAN には露出させない）。
      networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8888 ];

      services.searx = {
        enable = true;
        package = pkgs.searxng;
        environmentFile = config.sops.secrets."searxng".path;
        settings = {
          server = {
            port = 8888;
            # 0.0.0.0 でリッスンするが、上の firewall 設定で実際に到達できるのは
            # tailscale0 経由のみ。
            bind_address = "0.0.0.0";
            secret_key = "@SEARX_SECRET_KEY@";
          };
          # ahmia/torch は Tor プロキシ必須、radio browser はキャッシュ DB の
          # 初期化に失敗して登録できないため、いずれも無効化しておく。
          engines = [
            { name = "ahmia";         disabled = true; }
            { name = "torch";         disabled = true; }
            { name = "radio browser"; disabled = true; }
          ];
          search.formats = [ "html" "json" ];
        };
      };
    };
}
