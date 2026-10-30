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
      };
    };
}
