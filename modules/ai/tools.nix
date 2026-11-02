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
          # v0.3.1; the tag is pinned as a commit so it cannot be moved upstream.
          rev = "6d5906f07a6ea2b2a871271d9f3074157602d15f";
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
