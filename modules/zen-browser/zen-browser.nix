let
  # Zen on every desktop, Linux and darwin alike. On darwin the home-manager
  # module keeps the signed .app untouched (packageMode = "signed", the
  # default) and routes policies through macOS defaults and native messaging
  # hosts through ~/Library, which covers everything used here.
  common =
    { inputs, pkgs, ... }:
    {
      imports = [
        inputs.zen-browser.homeModules.twilight
      ];

      programs.zen-browser = {
        enable = true;
        nativeMessagingHosts = [ pkgs.tridactyl-native ];
      };

      home.file.".config/tridactyl" = {
        source = ./tridactyl;
        recursive = true;
      };
    };
in
{
  flake.modules.homeManager."desktop/darwin" = common;

  flake.modules.homeManager."desktop/linux" =
    { pkgs, ... }:
    {
      imports = [ common ];

      # MozillaのGFXブロックリスト(gfx.blacklist.dmabuf / gl.threadsafe)を
      # 上書きし、HWアクセラレーション(WebRender/VA-API)を強制有効化する
      programs.zen-browser.policies.Preferences = {
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
    };
}
