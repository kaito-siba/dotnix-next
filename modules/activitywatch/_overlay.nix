final: prev:
let
  # aw-server-rust master tip (contains PR #528 which fixes `aw-sync --buckets`).
  # Bump rev + hashes when moving forward; `nix build` will report mismatches.
  rev = "7c33810cd44393b3ecad64277b7e69bfeaee817b";
  srcHash = "sha256-/X+z24ZrehmvtdOT/x1Q9+nIJZJ+1SrhPfofIVlUrBU=";
  cargoHash = "sha256-1ud2g+AoDPWzDjdt2gZwA04AuTfn4lhb9kOmq9YcQnc=";
in
{
  aw-server-rust = prev.aw-server-rust.overrideAttrs (old: {
    version = "unstable-${builtins.substring 0 7 rev}";

    src = final.fetchFromGitHub {
      owner = "ActivityWatch";
      repo = "aw-server-rust";
      inherit rev;
      hash = srcHash;
      fetchSubmodules = true;
    };

    # The v0.13.2 version-override patch targets the release tag and no longer
    # applies cleanly to master. Replace with our clap-downcast fix.
    patches = [ ./aw-sync-fix-buckets.patch ];

    cargoDeps = final.rustPlatform.fetchCargoVendor {
      src = final.fetchFromGitHub {
        owner = "ActivityWatch";
        repo = "aw-server-rust";
        inherit rev;
        hash = srcHash;
        fetchSubmodules = true;
      };
      hash = cargoHash;
    };

    # Upstream restricts to linux but the Rust code builds on darwin.
    meta = old.meta // {
      platforms = old.meta.platforms ++ [ "x86_64-darwin" "aarch64-darwin" ];
    };
  });
}
