{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage {
  pname = "cship";
  version = "1.8.3";

  src = fetchFromGitHub {
    owner = "stephenleo";
    repo = "cship";
    # v1.8.3; the tag is pinned as a commit so it cannot be moved upstream.
    rev = "c49ce1920166b109657342ce1a4daf31d2825b6d";
    hash = "sha256-wGav3UXcN8UzeY8vFZgILSi1OZSHk9hqpm9/0P1D36c=";
  };

  cargoHash = "sha256-X9V/oAe7HdhLdF9YCVzzfPyKpV76o1Hrq6Tph5dpUn0=";

  meta = {
    description = "Starship-style status line for Claude Code";
    homepage = "https://github.com/stephenleo/cship";
    license = lib.licenses.asl20;
    mainProgram = "cship";
  };
}
