#!/usr/bin/env python3
"""Cooling-period check for flake inputs.

Every reachable input except the stable nixpkgs channel (and whatever
follows it) must point at a commit at least cooling_days old: a freshly
published malicious release is usually found within days, and nothing here
needs same-day updates. The commit date is `locked.lastModified` in
flake.lock, so no network access is needed. That date is what upstream's git
says it is, so this is a delay against accidents and the common attack, not
a proof of age.

Usage: cooling.py NEW.lock [OLD.lock]
With OLD.lock only inputs whose locked identity changed are checked (rev,
narHash, or source); without it, all. Exit 1 when any checked input is too
young.
"""
import os
import sys
import time
import tomllib
from pathlib import Path

import lockgraph

ROOT = Path(__file__).resolve().parent.parent
EXEMPT_ROOT = "nixpkgs"  # the stable channel: upstream review is the cooling period


def cooling_days():
    if "COOLING_DAYS" in os.environ:
        return int(os.environ["COOLING_DAYS"])
    with open(ROOT / "config.toml", "rb") as f:
        return int(tomllib.load(f).get("cooling_days", 7))


def main():
    days = cooling_days()
    new = lockgraph.walk(lockgraph.load(sys.argv[1]))
    old = lockgraph.walk(lockgraph.load(sys.argv[2])) if len(sys.argv) > 2 and os.path.exists(sys.argv[2]) else None
    paths = lockgraph.changed(old, new) if old is not None else sorted(new)
    now = time.time()
    rows, bad = [], []
    for path in paths:
        locked = new[path]["locked"]
        exempt = path == EXEMPT_ROOT
        age = (now - locked["lastModified"]) / 86400
        ok = exempt or age >= days
        rows.append((path, (locked.get("rev") or locked.get("narHash", ""))[:12], age, "exempt" if exempt else ("ok" if ok else "TOO YOUNG")))
        if not ok:
            bad.append(path)
    print("| input | rev | age (days) | status |\n|---|---|---|---|")
    for path, rev, age, status in rows:
        print(f"| {path} | {rev} | {age:.1f} | {status} |")
    if not rows:
        print("| (no input changed) | | | |")
    if bad:
        print(f"\nInputs younger than {days} days: {', '.join(bad)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
