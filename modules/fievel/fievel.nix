{
  # fievel: キーボードでマウス操作 (F3 / D+F で HJKL 移動、Super+Space でヒント
  # クリック) + ホームロウ mod のリマッパー。evdev でキーボードを grab し、
  # uinput の仮想キーボード・ポインタから出力する。
  #
  # xremap の後段に置く: 物理キーボード → xremap → fievel → niri。
  # fievel は既定だと 2 秒おきに全キーボードを探して grab するので、rebuild で
  # xremap が再起動した隙に物理キーボードを先に掴まれ、xremap の modmap が
  # 外れる。xremap は全ホストで全キーボードを grab しているので、fievel には
  # udev で固定名を振った xremap の仮想デバイスだけを --device で読ませる。
  # xremap が再起動するとデバイスが消えて fievel は異常終了するが、systemd が
  # 再起動して新しいデバイスに付き直す。
  #
  # 権限は input グループ (全キーボードを読める) を避け、xremap の出力デバイス
  # だけを fievel グループに開放する。出力用に uinput グループも要る。
  # グループ追加後は再ログインが必要。
  flake.modules.nixos.fievel =
    { config, lib, ... }:
    {
      hardware.uinput.enable = true;

      users.groups.fievel = { };

      services.udev.extraRules = ''
        SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="xremap", SYMLINK+="input/xremap", GROUP="fievel", MODE="0660"
      '';

      users.users = lib.genAttrs (lib.attrNames config.home-manager.users) (_: {
        extraGroups = [
          "fievel"
          "uinput"
        ];
      });
    };

  flake.modules.homeManager.fievel =
    {
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      src = inputs.fievel;

      fievel = pkgs.rustPlatform.buildRustPackage {
        pname = "fievel";
        version = (lib.importTOML "${src}/Cargo.toml").package.version;
        inherit src;
        cargoLock.lockFile = "${src}/Cargo.lock";

        meta = {
          description = "Keyboard-driven mouse control and key remapping for Linux";
          homepage = "https://github.com/MontyTheSoftwareEngineer/fievel";
          license = lib.licenses.mit;
          mainProgram = "fievel";
          platforms = lib.platforms.linux;
        };
      };
    in
    {
      # --odometer などの CLI 用
      home.packages = [ fievel ];

      xdg.configFile."fievel/fievel.config".source = ./fievel.config;

      systemd.user.services.fievel = {
        Unit = {
          Description = "Keyboard-driven mouse control";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          # xremap の再起動のたびに落ちるので起動回数制限を外す
          StartLimitIntervalSec = 0;
          X-Restart-Triggers = [ "${./fievel.config}" ];
        };

        Service = {
          Type = "simple";
          ExecStart = "${lib.getExe fievel} --device /dev/input/xremap";
          Restart = "always";
          RestartSec = 1;
        };

        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    };
}
