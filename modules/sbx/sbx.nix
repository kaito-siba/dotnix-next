{
  nixpkgs.allowedUnfreePackages = [ "sbx" ];

  # Docker Sandboxes: AI エージェントを microVM の sandbox で動かす。
  # NixOS は公式非対応なので tarball を自前で包む。AppArmor は NixOS では
  # 無効で userns も制限されていないため、公式パッケージの profile は不要。
  # /dev/kvm は systemd の udev が 0666 にするので kvm グループも要らない。
  flake.modules.nixos.sbx = {
    # 認証情報を secret service に保存する。niri モジュールも暗黙に有効化するが、
    # それに依存しないようここでも宣言する。
    services.gnome.gnome-keyring.enable = true;
  };

  flake.modules.homeManager.sbx =
    { pkgs, lib, ... }:
    let
      sbx = pkgs.callPackage ./_package.nix { };
    in
    {
      # remote control と Claude in Chrome は、各ホストで `sbx settings set claude.remoteControl true` と `sbx settings set claude.chrome true` を手で実行して有効にする。
      # この 2 つに対応する環境変数は無く、override を置く ~/.config/sandboxes/sandboxes/settings.json は daemon が書き換える file なので、nix では持たない
      home.packages = [ sbx ];

      # CLI は daemon が居ないと、自分の環境で `sbx daemon start` を起こす。herdr の端末から起こされた daemon は、その端末の HC_SCOPE を継ぐので、端末を閉じた時に herdr-core に kill される。その時、他の端末の sandbox も全て落ちる。端末と関わりの無い user service で動かす。
      # 起こし直すのは `systemctl --user restart sbx-daemon` で行う。`sbx daemon restart` は、呼んだ端末の環境で daemon を起こし直す。CLI に自動起動を止める設定は無いので、`systemctl --user stop sbx-daemon` で止めている間に CLI を使っても、呼んだ端末の環境で daemon が起きる
      systemd.user.services.sbx-daemon = {
        Unit = {
          Description = "Docker Sandboxes daemon";
          # login keyring は greetd の login で開く。それより前に起きた daemon は、起こし直すまで keychain の認証情報を読めない
          After = [ "graphical-session.target" ];
          # daemon が止まると全ての sandbox が落ちるので、switch では起こし直さない。sbx を上げた後は、sandbox を使っていない時に手で起こし直す
          X-RestartIfChanged = false;
        };
        Service = {
          # --detach を付けなければ foreground で動く
          ExecStart = "${lib.getExe sbx} daemon start";
          # sandbox の VM は、SIGTERM を受けた daemon が in-flight の request を最大 5 秒待ってから畳む。SIGTERM は先に daemon にだけ送る
          KillMode = "mixed";
          TimeoutStopSec = 30;
          # `sbx daemon stop` で正常に終わっても起こし直す。止まったままだと、次に CLI を呼んだ端末の環境で daemon が起きる
          Restart = "always";
          RestartSec = 5;
        };
        # logout した後も Mac から herdr-core connect で sandbox を使えるよう、PartOf は付けない
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
