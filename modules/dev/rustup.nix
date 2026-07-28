{
  # Toolchains managed by rustup itself. Mutually exclusive with dev/rust,
  # whose nixpkgs cargo/rustc would collide with the rustup proxies on PATH.
  flake.modules.homeManager."dev/rustup" =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        rustup
      ];
    };
}
