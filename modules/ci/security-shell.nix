{
  # Everything security/scripts/*.py needs beyond the standard library, pinned
  # by this flake's nixpkgs: vulnix for NVD matching and the cvss library for
  # turning OSV's CVSS vectors into scores. Used by daily-security.yml via
  # `nix develop .#security` and the same way by hand.
  perSystem =
    { pkgs, ... }:
    {
      devShells.security = pkgs.mkShell {
        packages = [
          pkgs.vulnix
          (pkgs.python3.withPackages (p: [ p.cvss ]))
        ];
      };
    };
}
