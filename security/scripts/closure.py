#!/usr/bin/env python3
"""Enumerate the build-time derivation closure of every host configuration.

Nothing is built: `nix derivation show -r` instantiates the derivations and
prints them, which works for the darwin hosts on a Linux runner too. The
output is one JSON file mapping host -> { drvPath -> {name, pname, version} }.

Usage: closure.py OUT.json [FLAKE_REF]
"""
import json
import re
import subprocess
import sys

VERSION_RE = re.compile(r"^(.*?)-([0-9][^-]*(?:-[0-9][^-]*)*)$")


def nix(*args):
    return subprocess.run(
        ["nix", "--extra-experimental-features", "nix-command flakes", *args],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def hosts(flake):
    out = {}
    for attr, tail in (
        ("nixosConfigurations", "config.system.build.toplevel"),
        ("darwinConfigurations", "system"),
    ):
        try:
            names = json.loads(nix("eval", "--json", f"{flake}#{attr}", "--apply", "builtins.attrNames"))
        except subprocess.CalledProcessError:
            continue
        for n in names:
            out[n] = f"{flake}#{attr}.{n}.{tail}"
    return out


def split_name(name):
    """'foo-1.2.3' -> ('foo', '1.2.3'); names without a version keep version ''."""
    if name.endswith(".drv"):
        name = name[:-4]
    m = VERSION_RE.match(name)
    if m:
        return m.group(1), m.group(2)
    return name, ""


def closure(target):
    data = json.loads(nix("derivation", "show", "-r", target))
    drvs = data.get("derivations", data)
    out = {}
    for path, drv in drvs.items():
        # nix >= 2.34 prints bare store path basenames as keys.
        if not path.startswith("/"):
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
    flake = sys.argv[2] if len(sys.argv) > 2 else "."
    result = {}
    for host, target in sorted(hosts(flake).items()):
        print(f"{host}: {target}", file=sys.stderr)
        result[host] = closure(target)
        print(f"{host}: {len(result[host])} derivations", file=sys.stderr)
    with open(out_path, "w") as f:
        json.dump(result, f)


if __name__ == "__main__":
    main()
