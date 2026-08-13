{
  # TRCC Linux — Thermalright の CPU クーラー / AIO ポンプヘッドに載っている
  # LCD・LED を制御する GUI (Windows 版 TRCC 2.1.2 の Linux 移植)。
  #
  # 上流の NixOS モジュールが udev ルール (非 root でのデバイスアクセス)、
  # sg カーネルモジュール、usb-storage の quirks までまとめて面倒を見る。
  # 常駐デーモンは無く、GUI を起動したときだけデバイスを叩く。
  flake.modules.nixos.trcc =
    { inputs, ... }:
    {
      imports = [ inputs.trcc-linux.nixosModules.default ];

      programs.trcc-linux.enable = true;
    };
}
