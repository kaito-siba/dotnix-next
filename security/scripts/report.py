#!/usr/bin/env python3
"""Markdown report for an update PR: what moved in flake.lock (every reachable
input, transitive ones included) and what that changes in every host's
derivation closure.

Usage: report.py OLD.lock NEW.lock OLD-closure.json NEW-closure.json [--max-bytes N]

With --max-bytes the per-host detail lists are shortened until the whole
report fits (a PR body is capped at 64 KiB); the full report should go to an
artifact. Without it nothing is cut.
"""
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone

import lockgraph


def when(ts):
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%d")


def lock_section(old, new):
    o, n = lockgraph.walk(old), lockgraph.walk(new)
    lines = ["## flake.lock", "", "| input | old | new | age (days) | compare |", "|---|---|---|---|---|"]
    now = datetime.now(timezone.utc).timestamp()
    for path in lockgraph.changed(o, n):
        on, nn = o.get(path), n[path]
        orev = (on or {}).get("locked", {}).get("rev") or (on or {}).get("locked", {}).get("narHash", "")
        nrev = nn["locked"].get("rev") or nn["locked"].get("narHash", "")
        orig = nn.get("original", {})
        compare = ""
        if orig.get("type") == "github" and on and on["locked"].get("rev") and nn["locked"].get("rev"):
            compare = f"https://github.com/{orig['owner']}/{orig['repo']}/compare/{on['locked']['rev'][:12]}...{nn['locked']['rev'][:12]}"
        age = (now - nn["locked"]["lastModified"]) / 86400
        old_s = f"{orev[:8]} ({when(on['locked']['lastModified'])})" if on else "(new)"
        new_s = f"{nrev[:8]} ({when(nn['locked']['lastModified'])})"
        lines.append(f"| {path} | {old_s} | {new_s} | {age:.0f} | {compare} |")
    if len(lines) == 4:
        lines.append("| (no input changed) | | | | |")
    return "\n".join(lines)


def by_pname(closure):
    out = defaultdict(set)
    for d in closure.values():
        out[d["pname"]].add(d["version"])
    return out


def capped(items, max_rows):
    items = list(items)
    if max_rows is not None and len(items) > max_rows:
        return items[:max_rows] + [f"- … and {len(items) - max_rows} more (full report in the workflow artifact)"]
    return items


def closure_section(old, new, max_rows):
    lines = ["## Package changes per host", ""]
    for host in sorted(new):
        o, n = by_pname(old.get(host, {})), by_pname(new[host])
        added = sorted(set(n) - set(o))
        removed = sorted(set(o) - set(n))
        bumped = sorted(p for p in set(n) & set(o) if n[p] != o[p])
        lines += [f"### {host}", "", f"added {len(added)}, removed {len(removed)}, version changed {len(bumped)}", ""]
        for title, rows in (
            ("version changes", [f"| {p} | {', '.join(sorted(o[p]))} | {', '.join(sorted(n[p]))} |" for p in bumped]),
            ("added", [f"- {p} {', '.join(sorted(n[p]))}" for p in added]),
            ("removed", [f"- {p} {', '.join(sorted(o[p]))}" for p in removed]),
        ):
            if not rows or max_rows == 0:
                continue
            lines.append(f"<details><summary>{title}</summary>\n")
            if title == "version changes":
                lines.append("| package | old | new |\n|---|---|---|")
            lines.extend(capped(rows, max_rows))
            lines.append("\n</details>\n")
    return "\n".join(lines)


def render(old_lock, new_lock, old_cl, new_cl, max_rows):
    return lock_section(old_lock, new_lock) + "\n\n" + closure_section(old_cl, new_cl, max_rows)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    max_bytes = None
    if "--max-bytes" in sys.argv:
        max_bytes = int(sys.argv[sys.argv.index("--max-bytes") + 1])
        args = [a for a in args if a != str(max_bytes)]
    old_lock, new_lock, old_cl, new_cl = (json.load(open(p)) for p in args[:4])
    for max_rows in (None, 80, 40, 20, 10, 0):
        text = render(old_lock, new_lock, old_cl, new_cl, max_rows)
        if max_bytes is None or len(text.encode()) <= max_bytes:
            break
    print(text)


if __name__ == "__main__":
    main()
