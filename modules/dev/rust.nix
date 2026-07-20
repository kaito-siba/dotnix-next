{
  flake.modules.homeManager."dev/rust" =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        rust-analyzer
        cargo
        rustc
        clippy
        rustfmt
      ];

      # rust-analyzer cannot locate the standard library sources on its own when
      # rustc comes from nixpkgs rather than rustup.
      home.sessionVariables.RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
    };
}
