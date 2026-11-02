#!/usr/bin/env python3
"""Markdown report for an update PR: what moved in flake.lock and what that
changes in every host's derivation closure.

Usage: report.py OLD.lock NEW.lock OLD-closure.json NEW-closure.json
"""
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone


def leaves(lock):
    root = lock["nodes"][lock["root"]]
    out = {}
    for name, ref in root["inputs"].items():
        if isinstance(ref, list):
            continue
        out[name] = lock["nodes"][ref]
    return out


def when(ts):
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%d")


def lock_section(old, new):
    o, n = leaves(old), leaves(new)
    lines = ["## flake.lock", "", "| input | old | new | age (days) | compare |", "|---|---|---|---|---|"]
    now = datetime.now(timezone.utc).timestamp()
    changed = 0
    for name in sorted(n):
        on, nn = o.get(name), n[name]
        orev, nrev = (on or {}).get("locked", {}).get("rev"), nn["locked"].get("rev")
        if on is not None and orev == nrev:
            continue
        changed += 1
        orig = nn.get("original", {})
        compare = ""
        if orig.get("type") == "github" and orev and nrev:
            compare = f"https://github.com/{orig['owner']}/{orig['repo']}/compare/{orev[:12]}...{nrev[:12]}"
        age = (now - nn["locked"]["lastModified"]) / 86400
        old_s = f"{(orev or '')[:8]} ({when(on['locked']['lastModified'])})" if on else "(new)"
        new_s = f"{(nrev or '')[:8]} ({when(nn['locked']['lastModified'])})"
        lines.append(f"| {name} | {old_s} | {new_s} | {age:.0f} | {compare} |")
    if changed == 0:
        lines.append("| (no input changed) | | | | |")
    return "\n".join(lines)


# PR bodies are capped at 64 KiB; the full report goes to the step summary.
MAX_ROWS = int(os.environ.get("REPORT_MAX_ROWS", "80"))


def capped(items):
    items = list(items)
    if len(items) > MAX_ROWS:
        return items[:MAX_ROWS] + [f"- … and {len(items) - MAX_ROWS} more"]
    return items


def by_pname(closure):
    out = defaultdict(set)
    for d in closure.values():
        out[d["pname"]].add(d["version"])
    return out


def closure_section(old, new):
    lines = ["## Package changes per host", ""]
    for host in sorted(new):
        o, n = by_pname(old.get(host, {})), by_pname(new[host])
        added = sorted(set(n) - set(o))
        removed = sorted(set(o) - set(n))
        bumped = sorted(p for p in set(n) & set(o) if n[p] != o[p])
        lines.append(f"### {host}")
        lines.append("")
        lines.append(f"added {len(added)}, removed {len(removed)}, version changed {len(bumped)}")
        lines.append("")
        if bumped:
            lines.append("<details><summary>version changes</summary>\n")
            lines.append("| package | old | new |\n|---|---|---|")
            lines.extend(capped(f"| {p} | {', '.join(sorted(o[p]))} | {', '.join(sorted(n[p]))} |" for p in bumped))
            lines.append("\n</details>\n")
        if added:
            lines.append("<details><summary>added</summary>\n")
            lines.extend(capped(f"- {p} {', '.join(sorted(n[p]))}" for p in added))
            lines.append("\n</details>\n")
        if removed:
            lines.append("<details><summary>removed</summary>\n")
            lines.extend(capped(f"- {p} {', '.join(sorted(o[p]))}" for p in removed))
            lines.append("\n</details>\n")
    return "\n".join(lines)


def main():
    old_lock, new_lock, old_cl, new_cl = (json.load(open(p)) for p in sys.argv[1:5])
    print(lock_section(old_lock, new_lock))
    print()
    print(closure_section(old_cl, new_cl))


if __name__ == "__main__":
    main()
