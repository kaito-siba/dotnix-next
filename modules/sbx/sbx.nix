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
    { pkgs, ... }:
    {
      home.packages = [ (pkgs.callPackage ./_package.nix { }) ];
    };
}
