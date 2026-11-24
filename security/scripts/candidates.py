#!/usr/bin/env python3
"""Cooled update of flake inputs: lock what was the branch HEAD a week ago.

`nix flake update` locks every input's HEAD, and an active upstream's HEAD is
always younger than the cooling period, so checking the updated lock for age
holds back every input for the youngest one. Instead each weekly run records
every input's HEAD as a candidate together with when it was seen, and a later
run locks the candidate once it has been on the branch for the cooling period.
The period then counts from when this repository saw the commit, not only
from the commit date upstream wrote into it, and nixpkgs-unstable gets a rev
that really was the channel's HEAD (so the binary cache has it).

Usage: candidates.py CURRENT.lock HEAD.lock CANDIDATES.json OVERRIDES.txt
CURRENT.lock is flake.lock as merged, HEAD.lock the same flake after `nix
flake update` of the inputs. CANDIDATES.json is rewritten in place,
OVERRIDES.txt gets one "NAME URL" line per candidate to lock (for `nix flake
lock --override-input`), and the markdown for the PR body goes to stdout.

Per input (every root input except the stable nixpkgs and `follows`):
- a candidate is locked once it was seen cooling_days - SLACK_DAYS ago, its
  commit is cooling_days old (what pr-check's cooling.py checks), and it is
  still an ancestor of the branch HEAD;
- a candidate that is not due yet is kept as is: replacing it with a newer
  HEAD would restart its clock;
- a candidate is dropped when flake.nix now points the input elsewhere, when
  the lock already has it, or when upstream force-pushed it away;
- otherwise a HEAD that differs from the lock becomes the new candidate.
A locked input whose HEAD has moved on since shows up twice in the table:
once as locked, once as next week's candidate.
"""
import json
import subprocess
import sys
import time
from datetime import datetime, timezone

import lockgraph
from cooling import EXEMPT_ROOT, cooling_days

# Weekly cron runs start minutes apart from week to week; without slack a
# candidate seen at 00:10 last Saturday would not be due at 00:05 today.
SLACK_DAYS = 1
ISO = "%Y-%m-%dT%H:%M:%SZ"


def root_inputs(lock):
    """{name: node} for the root inputs that are locked on their own."""
    refs = lock["nodes"][lock["root"]]["inputs"]
    return {n: lock["nodes"][r] for n, r in refs.items() if n != EXEMPT_ROOT and not isinstance(r, list)}


def candidate(node, observed):
    locked = node["locked"]
    return {
        "rev": locked["rev"],
        "url": f"github:{locked['owner']}/{locked['repo']}/{locked['rev']}",
        "lastModified": locked["lastModified"],
        "observed": observed,
        "original": node["original"],
    }


def is_ancestor(locked, rev, head):
    if rev == head:
        return True
    r = subprocess.run(
        ["gh", "api", f"repos/{locked['owner']}/{locked['repo']}/compare/{rev}...{head}?per_page=1", "--jq", ".status"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        sys.exit(f"compare {locked['owner']}/{locked['repo']} {rev[:12]}...{head[:12]}: {r.stderr.strip()}")
    return r.stdout.strip() in ("ahead", "identical")


def compare_link(locked, base, head):
    if base == head:
        return ""
    return f"https://github.com/{locked['owner']}/{locked['repo']}/compare/{base[:12]}...{head[:12]}"


def main():
    current_lock, head_lock, cands_path, overrides_path = sys.argv[1:5]
    days = cooling_days()
    now = time.time()
    observed_now = datetime.fromtimestamp(now, timezone.utc).strftime(ISO)
    current = root_inputs(lockgraph.load(current_lock))
    head = root_inputs(lockgraph.load(head_lock))
    with open(cands_path) as f:
        cands = json.load(f)

    new_cands, overrides, rows = {}, [], []
    for name in sorted(head):
        hn, cn = head[name], current.get(name)
        hl = hn["locked"]
        cur_rev = (cn or {}).get("locked", {}).get("rev")
        if hl.get("type") != "github":
            if cn is None or lockgraph.identity(cn) != lockgraph.identity(hn):
                rows.append((name, "unsupported type: update by hand", "", "", "", ""))
            continue
        cand = cands.get(name)
        locks = cur_rev  # what flake.lock has for this input once the PR merges
        if cand and cand["original"] != hn["original"]:
            rows.append((name, "dropped: flake.nix points elsewhere", cand["rev"][:12], cand["observed"], "", ""))
            cand = None
        if cand and cand["rev"] == cur_rev:
            cand = None
        if cand and not is_ancestor(hl, cand["rev"], hl["rev"]):
            rows.append((name, "dropped: upstream force-pushed it off the branch", cand["rev"][:12], cand["observed"], "", ""))
            cand = None
        if cand:
            seen = (now - datetime.strptime(cand["observed"], ISO).replace(tzinfo=timezone.utc).timestamp()) / 86400
            age = (now - cand["lastModified"]) / 86400
            if seen >= days - SLACK_DAYS and age >= days:
                overrides.append(f"{name} {cand['url']}")
                locks = cand["rev"]
                rows.append((name, "locked", cand["rev"][:12], cand["observed"], f"{age:.1f}", ""))
            else:
                new_cands[name] = cand
                rows.append((name, "waiting", cand["rev"][:12], cand["observed"], f"{age:.1f}", compare_link(hl, cur_rev, hl["rev"]) if cur_rev else ""))
                continue
        if hl["rev"] != locks:
            new_cands[name] = candidate(hn, observed_now)
            rows.append((name, "new candidate", hl["rev"][:12], observed_now, f"{(now - hl['lastModified']) / 86400:.1f}", compare_link(hl, locks, hl["rev"]) if locks else ""))

    with open(cands_path, "w") as f:
        json.dump(new_cands, f, indent=2, sort_keys=True)
        f.write("\n")
    with open(overrides_path, "w") as f:
        f.writelines(line + "\n" for line in overrides)

    print("| input | status | rev | observed | age (days) | not in the lock after merge |\n|---|---|---|---|---|---|")
    for row in rows:
        print("| " + " | ".join(row) + " |")
    if not rows:
        print("| (nothing moved) | | | | | |")


if __name__ == "__main__":
    main()
