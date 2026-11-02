{
  # `nix flake init -t github:kaito-siba/dotnix-next#<name>` drops a flake.nix
  # and .envrc into a new repository. Each template pins nixos-26.05 on its
  # own, so a project does not move when this flake's lock does.
  flake.templates = {
    node = {
      path = ../../templates/node;
      description = "Node.js: nodejs, pnpm, biome";
    };
    rust = {
      path = ../../templates/rust;
      description = "Rust: cargo, rustc, clippy, rustfmt, rust-analyzer";
    };
    python = {
      path = ../../templates/python;
      description = "Python: python3, uv, ruff";
    };
    react-native = {
      path = ../../templates/react-native;
      description = "React Native: node, watchman, JDK 17, Android SDK (cocoapods on darwin)";
    };
  };
}
