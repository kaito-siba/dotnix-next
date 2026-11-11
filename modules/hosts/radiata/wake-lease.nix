{
  flake.modules.nixos."hosts/radiata" =
    { config, ... }:
    {
      # twit-curator の Podcast 用 TTS (anime-tts-factory の Irodori-TTS-Server)。
      # WoL で起こされ、合成が終わったら suspend する
      systemd.services.tts = {
        description = "Irodori-TTS-Server (anime-tts-factory)";
        after = [ "network-online.target" "tailscaled.service" ];
        wants = [ "network-online.target" ];
        path = [ config.nix.package "/run/current-system/sw" ];
        serviceConfig = {
          User = "rkv12";
          WorkingDirectory = "/home/rkv12/repos/github.com/kaito-siba/anime-tts-factory";
          ExecStart = "/run/current-system/sw/bin/nix develop --command atf irodori serve main5 --checkpoint checkpoint_0001500";
          Restart = "on-failure";
          RestartSec = 10;
        };
      };
      networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 8088 ];

      wake-lease.services.tts = {
        healthUrl = "http://100.94.128.11:8088/health";
        allowedNodes = [ "twit-curator" ];
      };
    };
}
