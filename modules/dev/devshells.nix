{
  # Shared devShells for repositories that cannot carry a flake.nix of their
  # own (team projects that run on mise): a git-ignored .envrc with
  #   use flake ~/repos/github.com/kaito-siba/dotnix-next#node
  # takes the toolchain from here while mise stays the task runner. Projects
  # that can commit a flake start from `nix flake init -t <this flake>#node`
  # instead (templates.nix); the shells below and the templates are kept in
  # step by hand.
  #
  # Only toolchains live here. Editor-facing tools (LSPs, formatters) stay in
  # the home profile via modules/dev/*.nix so neovim finds them everywhere.
  perSystem =
    { pkgs, ... }:
    {
      devShells = {
        node = pkgs.mkShell {
          packages = with pkgs; [
            nodejs
            pnpm
            biome
          ];
        };

        rust = pkgs.mkShell {
          packages = with pkgs; [
            cargo
            rustc
            clippy
            rustfmt
            rust-analyzer
          ];
          RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
        };

        python = pkgs.mkShell {
          packages = with pkgs; [
            python3
            uv
            ruff
          ];
        };
      };
    };
}
