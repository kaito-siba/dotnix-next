{
  description = "brand-new nix configuration";

  # 更新経路の層分け (供給網対策)。
  #   stable     : nixpkgs (nixos-26.05)。ほぼ全部ここから。stable channel の
  #                遅延と backport レビューが冷却期間を兼ねる。
  #   例外       : nixpkgs-unstable から取るのは keifu / yt-dlp / codex と
  #                claude-code だけ。更新は週 1 の CI PR 経由で、新 rev が 7 日
  #                未満なら CI が落とす。
  #   直接 input : 下の nixpkgs 以外の flake input。lock で rev 固定、同じ
  #                冷却チェックの対象。inputs.nixpkgs.follows は stable に揃える。
  #   バイナリ pin: URL に commit を書いたもの (look) と fetchurl の hash 固定
  #                (defi / smoothcsv)。`nix flake update` では動かず手で上げる。
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # llama-cpp は cudaSupport = true でビルドするため binary cache が一切効かず
    # (cache.nixos.org は unfree な CUDA redist をビルドしない)、nixpkgs-unstable
    # を追うと更新のたびに ggml-cuda の全コンパイルが走る。llama 用だけ rev を
    # 固定し、上げたいときに手で書き換える。
    nixpkgs-llama.url = "github:NixOS/nixpkgs/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    import-tree.url = "github:vic/import-tree";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    claude-code = {
      url = "github:sadjow/claude-code-nix?ref=latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    herdr = {
      url = "github:ogulcancelik/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # v5 (C++ native rewrite). Deliberately does NOT follow our nixpkgs:
    # overriding inputs changes the derivation hash and loses the
    # noctalia.cachix.org binary cache.
    noctalia.url = "github:noctalia-dev/noctalia";

    xremap = {
      url = "github:xremap/nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sqlit = {
      url = "github:Maxteabag/sqlit";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Thermalright の LCD/LED コントロールセンター。リリースタグ v9.9.5 より後に
    # NixOS 向けの udev ルール修正が入っているため default ブランチを追う。
    trcc-linux = {
      url = "github:Lexonight1/thermalright-trcc-linux";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # キーボードでマウス操作するツール。flake を持たないのでソースだけ取り込み、
    # modules/fievel でビルドする。`nix flake update fievel` で追従する。
    fievel = {
      url = "github:MontyTheSoftwareEngineer/fievel";
      flake = false;
    };

    # macOS の launcher。darwin 向けは署名済み bundle の fetchurl で、ソース
    # ビルドはできない (Xcode が要る)。release tag の commit には flake.nix が
    # 無いので main の commit で固定し、上げる
    # ときは upstream の release から 7 日以上空ける。look.cachix の鍵は darwin
    # では何もビルドしないので追加しない。
    look = {
      url = "github:kunkka19xx/look/c52825e59341d5c6c38359f07c8c2728cca9f03a";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    { import-tree, flake-parts, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ (import-tree ./modules) ];

      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
    };
}
