{
  # Key remapping daemon. Device specific modmaps live in each host module.
  flake.modules.nixos.xremap =
    { inputs, ... }:
    {
      imports = [ inputs.xremap.nixosModules.default ];

      services.xremap = {
        enable = true;
        withNiri = true;
        # fievel は xremap の出力を読んで仮想キーボードに書き戻すので、xremap が
        # fievel より後に起動するとそれも grab してループになる。名前は部分一致。
        extraArgs = [
          "--ignore"
          "fievel"
        ];

        # herdr の prefix (modules/shell/herdr/config.toml)。IME が有効だと
        # prefix の次のキーを mozc が入力として食べるので、先に IME を切る。
        # xremap は IME の状態を読めないので、切ったままで元には戻さない。
        # system service の xremap には NIRI_SOCKET が無く application で
        # 絞れないので、全 window に効く。
        config.keymap = [
          {
            name = "IME off on herdr prefix";
            remap."C-space" = [
              "Muhenkan"
              "C-space"
            ];
          }
        ];
      };
    };
}
