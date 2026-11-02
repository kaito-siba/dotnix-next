{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      forEach =
        f:
        nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (
          system:
          f (
            import nixpkgs {
              inherit system;
              # The Android SDK is unfree and asks for its license here.
              config.allowUnfree = true;
              config.android_sdk.accept_license = true;
            }
          )
        );
    in
    {
      devShells = forEach (
        pkgs:
        let
          # Pin the SDK pieces per project: old apps need old build tools.
          android = pkgs.androidenv.composeAndroidPackages {
            platformVersions = [ "35" ];
            buildToolsVersions = [ "35.0.0" ];
            includeNDK = false;
            includeEmulator = false;
          };
        in
        {
          default = pkgs.mkShell {
            packages =
              with pkgs;
              [
                nodejs
                watchman
                jdk17
                android.androidsdk
              ]
              ++ lib.optionals stdenv.hostPlatform.isDarwin [ cocoapods ];
            ANDROID_HOME = "${android.androidsdk}/libexec/android-sdk";
            JAVA_HOME = pkgs.jdk17.home;
          };
        }
      );
    };
}
