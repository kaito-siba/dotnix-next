{
  flake.modules.homeManager.zen-browser =
    { inputs, pkgs, ... }:
    {
      imports = [
        inputs.zen-browser.homeModules.twilight
      ];

      programs.zen-browser = {
        enable = true;
        nativeMessagingHosts = [ pkgs.tridactyl-native ];

        # MozillaのGFXブロックリスト(gfx.blacklist.dmabuf / gl.threadsafe)を
        # 上書きし、HWアクセラレーション(WebRender/VA-API)を強制有効化する
        policies.Preferences = {
          "widget.dmabuf.force-enabled" = {
            Value = true;
            Status = "locked";
          };
          "gfx.webrender.all" = {
            Value = true;
            Status = "locked";
          };
          "media.ffmpeg.vaapi.enabled" = {
            Value = true;
            Status = "locked";
          };
          "media.hardware-video-decoding.force-enabled" = {
            Value = true;
            Status = "locked";
          };
          # 注: WebGLのゼロコピー(DMABUF_WEBGL)はNVIDIAバイナリドライバで
          # Firefox組み込みブロック(bug 1924578: canvas描画破損)のため有効化不可。
          # Google Earth等の重いWebGLはChromium系の方が速い(Firefox側のNVIDIA制約)。
        };
      };

      # VA-API tooling for hardware video decode.
      home.packages = with pkgs; [
        libva
        libva-utils
      ];

      systemd.user.sessionVariables = {
        MOZ_ENABLE_WAYLAND = "1";
        MOZ_WEBRENDER = "1";
        MOZ_DISABLE_RDD_SANDBOX = "1";
      };

      home.file.".config/tridactyl" = {
        source = ./tridactyl;
        recursive = true;
      };
    };
}
