#!/usr/bin/env python3
"""Enumerate the build-time derivation closure of every host configuration.

Nothing is built: `nix derivation show -r` instantiates the derivations and
prints them, which works for the darwin hosts on a Linux runner too.
Import-from-derivation is refused so that "evaluate" can never mean "build".
The output is one JSON file mapping host -> { drvPath -> {...} }.

Any evaluation error is fatal, and so is finding no host at all: weekly-update
merges on the strength of this script succeeding.

Usage: closure.py OUT.json [FLAKE_REF]
"""
import json
import re
import subprocess
import sys

VERSION_RE = re.compile(r"^(.*?)-([0-9][^-]*(?:-[0-9][^-]*)*)$")
NIX = [
    "nix",
    "--extra-experimental-features", "nix-command flakes",
    "--option", "allow-import-from-derivation", "false",
]


def nix(*args):
    r = subprocess.run([*NIX, *args], capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        raise SystemExit(f"nix {' '.join(args[:2])} failed ({r.returncode})")
    return r.stdout


def hosts(flake):
    """{host: installable} for every nixos / darwin configuration. One
    evaluation of the flake outputs, so an error anywhere in it is an error."""
    expr = (
        f'let f = builtins.getFlake "{flake}"; in '
        '{ nixosConfigurations = builtins.attrNames (f.nixosConfigurations or { }); '
        '  darwinConfigurations = builtins.attrNames (f.darwinConfigurations or { }); }'
    )
    found = json.loads(nix("eval", "--json", "--impure", "--expr", expr))
    out = {}
    for n in found["nixosConfigurations"]:
        out[n] = f"{flake}#nixosConfigurations.{n}.config.system.build.toplevel"
    for n in found["darwinConfigurations"]:
        out[n] = f"{flake}#darwinConfigurations.{n}.system"
    if not out:
        raise SystemExit("no nixosConfigurations or darwinConfigurations found")
    return out


def split_name(name):
    if name.endswith(".drv"):
        name = name[:-4]
    m = VERSION_RE.match(name)
    return (m.group(1), m.group(2)) if m else (name, "")


def closure(target):
    data = json.loads(nix("derivation", "show", "-r", target))
    drvs = data.get("derivations", data)
    out = {}
    for path, drv in drvs.items():
        if not path.startswith("/"):  # nix >= 2.34 prints bare basenames
            path = f"/nix/store/{path}"
        env = drv.get("env", {})
        name = drv.get("name") or path.split("-", 1)[1]
        pname, version = split_name(name)
        out[path] = {
            "name": name,
            "pname": env.get("pname") or pname,
            "version": env.get("version") or version,
            # vulnix reads CVE ids out of patch file names and drops those
            # from a package's findings, which is how nixpkgs backports show.
            "patches": env.get("patches", "").split(),
        }
    return out


def main():
    out_path = sys.argv[1]
    flake = sys.argv[2] if len(sys.argv) > 2 else "git+file://" + subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True
    ).stdout.strip()
    result = {}
    for host, target in sorted(hosts(flake).items()):
        result[host] = closure(target)
        print(f"{host}: {len(result[host])} derivations", file=sys.stderr)
    with open(out_path, "w") as f:
        json.dump(result, f)


if __name__ == "__main__":
    main()
