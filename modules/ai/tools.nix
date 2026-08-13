{
  flake.modules.homeManager.ai =
    { pkgs, ... }:
    let
      search-sessions = pkgs.rustPlatform.buildRustPackage {
        pname = "search-sessions";
        version = "0.3.1";

        src = pkgs.fetchFromGitHub {
          owner = "sinzin91";
          repo = "search-sessions";
          rev = "v0.3.1";
          hash = "sha256-Svsi3KrkO/zHhoSHdTNNmF7Lse8nd96d6ZLABto3wSA=";
        };

        cargoHash = "sha256-rXl6aESEKjc4v+Onmvcj9gVEAzVBVYfaOFsY1Yvnofc=";

        # Integration tests require real session files under $HOME (unavailable in sandbox).
        doCheck = false;
      };
    in
    {
      home.packages = [
        search-sessions
      ];
    };
}
