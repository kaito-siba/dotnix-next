#!/usr/bin/env python3
"""Cooling-period check for flake inputs.

Every input except the stable nixpkgs channel must point at a commit that is
at least COOLING_DAYS old: a freshly published malicious release is usually
found within days, and nothing in this flake needs same-day updates. The
commit date comes from `locked.lastModified` in flake.lock, so no network
access is needed.

Usage: cooling.py NEW.lock [OLD.lock]
With OLD.lock only inputs whose rev changed are checked; without it, all.
Exit 1 when any checked input is too young.
"""
import json
import os
import sys
import time

COOLING_DAYS = int(os.environ.get("COOLING_DAYS", "7"))
EXEMPT = {"nixpkgs"}  # the stable channel: upstream review is the cooling period


def leaves(lock):
    root = lock["nodes"][lock["root"]]
    for name, ref in root["inputs"].items():
        if isinstance(ref, list):  # follows
            continue
        yield name, lock["nodes"][ref]


def main():
    new = json.load(open(sys.argv[1]))
    old = json.load(open(sys.argv[2])) if len(sys.argv) > 2 and os.path.exists(sys.argv[2]) else None
    old_revs = {n: node["locked"].get("rev") for n, node in leaves(old)} if old else {}
    now = time.time()
    bad = []
    rows = []
    for name, node in leaves(new):
        locked = node["locked"]
        rev = locked.get("rev")
        if old is not None and old_revs.get(name) == rev:
            continue
        age_days = (now - locked["lastModified"]) / 86400
        exempt = name in EXEMPT
        ok = exempt or age_days >= COOLING_DAYS
        rows.append((name, (rev or "")[:12], age_days, "exempt" if exempt else ("ok" if ok else "TOO YOUNG")))
        if not ok:
            bad.append(name)
    print(f"| input | rev | age (days) | status |\n|---|---|---|---|")
    for name, rev, age, status in rows:
        print(f"| {name} | {rev} | {age:.1f} | {status} |")
    if bad:
        print(f"\nInputs younger than {COOLING_DAYS} days: {', '.join(bad)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
