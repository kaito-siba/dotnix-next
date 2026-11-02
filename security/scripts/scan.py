#!/usr/bin/env python3
"""Daily security scan over every host's derivation closure.

Three sources, each switchable in security/config.toml:

  vulnix  NVD CPE matching on every derivation (nixpkgs and flake inputs
          alike; fetchurl'd binaries are derivations with pname/version too).
  osv     OSV.dev for the ecosystems whose packages appear as derivations
          (PyPI, crates.io) plus explicitly listed npm packages. This is the
          source that carries MAL-* (malicious package) entries.
  ghsa    GitHub security advisories published by every GitHub repository the
          flake takes code from. Reported as-is, without version matching:
          small projects write affected ranges too loosely to trust a parser.

Findings are keyed per package+version (not per CVE: the fix is a version
bump either way). security/baseline.json holds the keys triaged by hand when
the scan was introduced; only keys outside it count as new. A new finding
becomes an Issue only when --issues is given and it has persisted for
persist_days (judged from earlier results in --history), so hits that
nixpkgs fixes within the week never turn into notifications.

Usage:
  scan.py --closure closure.json --lock flake.lock --out results.json
          [--history DIR] [--summary FILE] [--issues] [--fastlane]
"""
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import tomllib
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # security/
VULNIX_ATTEMPTS = 3
VULNIX_RETRY_SECONDS = 300


class ScannerError(Exception):
    """A scanner could not run; the others still do and the summary says so."""

REPO = ROOT.parent

PYPI_RE = re.compile(r"^python3(?:\.\d+)?-(?P<name>.+?)-(?P<ver>\d[^-]*)$")
CRATE_RE = re.compile(r"^(?:cargo-package-|crate-)(?P<name>.+?)-(?P<ver>\d[^-]*?)(?:\.tar\.gz)?$")
GH_OWNER_RE = re.compile(r'owner\s*=\s*"([^"]+)"\s*;\s*repo\s*=\s*"([^"]+)"', re.S)
GH_URL_RE = re.compile(r"github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/releases/download/")


def sh(*args, check=True, input=None):
    return subprocess.run(args, check=check, capture_output=True, text=True, input=input)


def load_config():
    with open(ROOT / "config.toml", "rb") as f:
        return tomllib.load(f)


# ---------------------------------------------------------------- closure

def merge_closure(closure):
    """host -> {drv -> info}  ==>  drv -> info + hosts"""
    merged = {}
    for host, drvs in closure.items():
        for path, info in drvs.items():
            m = merged.setdefault(path, dict(info, hosts=[]))
            m["hosts"].append(host)
    return merged


# ----------------------------------------------------------------- vulnix

def run_vulnix(merged, whitelist):
    # vulnix's text --from-file silently loads nothing (its paths never reach
    # the store), so hand it the packages.json shape instead: name plus patch
    # file names, no .drv files needed. Dedupe on (name, patches).
    pkgs = {}
    for path, d in merged.items():
        key = (d["name"], tuple(d.get("patches", [])))
        pkgs.setdefault(key, {"name": d["name"], "patches": [os.path.basename(x) for x in key[1]]})
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump({f"{i}": v for i, v in enumerate(pkgs.values())}, f)
        listfile = f.name
    cmd = ["vulnix", "--no-requisites", "--from-file", listfile, "--json"]
    if whitelist.exists():
        cmd += ["--whitelist", str(whitelist)]
    # NVD serves 404 around feed regeneration; a plain retry covers that.
    for attempt in range(VULNIX_ATTEMPTS):
        r = sh(*cmd, check=False)
        if r.returncode in (0, 2):
            break
        if attempt + 1 < VULNIX_ATTEMPTS:
            time.sleep(VULNIX_RETRY_SECONDS)
    else:
        last = r.stderr.strip().splitlines()[-1] if r.stderr.strip() else ""
        raise ScannerError(f"vulnix failed after {VULNIX_ATTEMPTS} attempts ({r.returncode}): {last}")
    by_name = defaultdict(list)
    for d in merged.values():
        by_name[d["name"]].append(d)
    findings = []
    for item in json.loads(r.stdout or "[]"):
        scores = item.get("cvssv3_basescore") or {}
        sev = max(scores.values(), default=0.0)
        hosts = sorted({h for d in by_name.get(item["name"], []) for h in d["hosts"]})
        findings.append({
            "key": f"vulnix:{item['pname']}:{item['version']}",
            "source": "vulnix",
            "pname": item["pname"],
            "version": item["version"],
            "ids": sorted(item["affected_by"]),
            "severity": sev,
            "hosts": hosts,
            "detail": "",
        })
    return findings


# -------------------------------------------------------------------- osv

def osv_queries(merged, extra):
    queries = {}
    for d in merged.values():
        name = d["name"]
        m = PYPI_RE.match(name)
        if m:
            queries[("PyPI", m["name"], m["ver"])] = d["hosts"]
            continue
        m = CRATE_RE.match(name)
        if m:
            queries[("crates.io", m["name"], m["ver"])] = d["hosts"]
    for e in extra:
        for d in merged.values():
            if d["pname"] == e["pname"] and d["version"]:
                queries[(e["ecosystem"], e["name"], d["version"])] = d["hosts"]
    return queries


def osv_post(path, body):
    req = urllib.request.Request(
        f"https://api.osv.dev/v1/{path}",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.load(resp)


def osv_get(path):
    with urllib.request.urlopen(f"https://api.osv.dev/v1/{path}", timeout=60) as resp:
        return json.load(resp)


def run_osv(merged, extra):
    queries = osv_queries(merged, extra)
    keys = sorted(queries)
    findings = []
    detail_cache = {}
    for i in range(0, len(keys), 500):
        chunk = keys[i:i + 500]
        body = {"queries": [
            {"package": {"name": n, "ecosystem": eco}, "version": v} for eco, n, v in chunk
        ]}
        results = osv_post("querybatch", body).get("results", [])
        for (eco, n, v), res in zip(chunk, results):
            vulns = res.get("vulns") or []
            if not vulns:
                continue
            ids = sorted(x["id"] for x in vulns)
            sev = 0.0
            summaries = []
            for vid in ids:
                if vid not in detail_cache:
                    try:
                        detail_cache[vid] = osv_get(f"vulns/{vid}")
                    except Exception:  # noqa: BLE001
                        detail_cache[vid] = {}
                det = detail_cache[vid]
                # OSV carries CVSS vectors, not scores; the GHSA-derived
                # records put a word in database_specific.severity.
                word = (det.get("database_specific") or {}).get("severity", "")
                sev = max(sev, {"CRITICAL": 9.5, "HIGH": 8.0, "MODERATE": 5.0, "MEDIUM": 5.0, "LOW": 2.0}.get(str(word).upper(), 0.0))
                if det.get("summary"):
                    summaries.append(f"{vid}: {det['summary']}")
            malicious = any(x["id"].startswith("MAL-") for x in vulns)
            findings.append({
                "key": f"osv:{eco}/{n}:{v}",
                "source": "osv",
                "pname": f"{eco}/{n}",
                "version": v,
                "ids": ids,
                "severity": 10.0 if malicious else sev,
                "hosts": sorted(set(queries[(eco, n, v)])),
                "detail": ("MALICIOUS PACKAGE. " if malicious else "") + "\n".join(summaries)[:2000],
            })
    return findings, len(keys)


# ------------------------------------------------------------------- ghsa

def github_repos(lock):
    repos = set()
    for node in lock["nodes"].values():
        orig = node.get("original") or {}
        if orig.get("type") == "github":
            repos.add((orig["owner"], orig["repo"]))
    for nix_file in (REPO / "modules").rglob("*.nix"):
        text = nix_file.read_text(errors="ignore")
        for owner, repo in GH_OWNER_RE.findall(text):
            repos.add((owner, repo))
        for owner, repo in GH_URL_RE.findall(text):
            repos.add((owner, repo))
    return sorted(repos)


def run_ghsa(lock):
    findings = []
    repos = github_repos(lock)
    for owner, repo in repos:
        r = sh("gh", "api", f"repos/{owner}/{repo}/security-advisories?state=published&per_page=20", check=False)
        if r.returncode != 0:
            continue
        for adv in json.loads(r.stdout or "[]"):
            sev = {"critical": 9.5, "high": 8.0, "medium": 5.0, "low": 2.0}.get(adv.get("severity"), 0.0)
            findings.append({
                "key": f"ghsa:{owner}/{repo}:{adv['ghsa_id']}",
                "source": "ghsa",
                "pname": f"{owner}/{repo}",
                "version": "",
                "ids": [x for x in (adv.get("ghsa_id"), adv.get("cve_id")) if x],
                "severity": sev,
                "hosts": [],
                "detail": f"{adv.get('summary', '')} (published {adv.get('published_at', '')[:10]}) {adv.get('html_url', '')}",
            })
    return findings, len(repos)


# --------------------------------------------------------------- fastlane

def attr_versions(ref, pnames):
    """Version of each pname as a top-level attribute of nixpkgs at `ref`
    ('' when the attribute does not exist or fails to evaluate)."""
    names = " ".join(json.dumps(p) for p in pnames)
    expr = (
        f'let p = (builtins.getFlake "{ref}").legacyPackages.x86_64-linux; '
        f'get = n: let r = builtins.tryEval (if builtins.hasAttr n p then (builtins.getAttr n p).version or "" else ""); '
        f'in if r.success then r.value else ""; '
        f'in builtins.listToAttrs (map (n: {{ name = n; value = get n; }}) [ {names} ])'
    )
    r = sh("nix", "--extra-experimental-features", "nix-command flakes", "eval", "--json", "--impure", "--expr", expr, check=False)
    return json.loads(r.stdout) if r.returncode == 0 else {}


def fastlane_candidates(lock, pnames):
    """vulnix hits whose nixpkgs attribute already moved on the channel HEAD.

    Derivation names carry suffixes (-bootstrap, -go-modules, -src) and one
    pname covers several derivations, so the comparison is between the locked
    nixpkgs and the channel HEAD for the same attribute, not against the
    derivation's own version string.
    """
    node = lock["nodes"][lock["nodes"][lock["root"]]["inputs"]["nixpkgs"]]
    orig, locked = node["original"], node["locked"]
    head_ref = f"github:{orig['owner']}/{orig['repo']}/{orig.get('ref', 'master')}"
    locked_ref = f"github:{locked['owner']}/{locked['repo']}/{locked['rev']}"
    head, cur = attr_versions(head_ref, pnames), attr_versions(locked_ref, pnames)
    return [(p, cur[p], head[p]) for p in pnames if cur.get(p) and head.get(p) and cur[p] != head[p]]


# ----------------------------------------------------------------- issues

def gh_json(*args):
    r = sh("gh", *args, check=False)
    return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else []


def sync_issues(findings, dry_run):
    label = "security"
    sh("gh", "label", "create", label, "--color", "B60205", "--description", "automated security scan", "--force", check=False)
    open_issues = gh_json("issue", "list", "--label", label, "--state", "open", "--limit", "500", "--json", "number,title,body")
    by_key = {}
    for iss in open_issues:
        m = re.search(r"<!-- key: (.*?) -->", iss.get("body") or "")
        if m:
            by_key[m.group(1)] = iss
    wanted = {f["key"]: f for f in findings}
    for key, f in wanted.items():
        if key in by_key:
            continue
        title = f"[security] {f['pname']} {f['version']} ({f['source']})".strip()
        body = "\n".join([
            f"<!-- key: {key} -->",
            f"**source**: {f['source']}  ",
            f"**package**: {f['pname']} {f['version']}  ",
            f"**severity**: {f['severity']}  ",
            f"**hosts**: {', '.join(f['hosts']) or '-'}  ",
            f"**ids**: {', '.join(f['ids'])}",
            "",
            f["detail"],
            "",
            "Opened by the daily security scan. It closes on its own once the finding disappears "
            "(version bump) or the key is added to security/baseline.json or the vulnix whitelist.",
        ])
        print(f"issue: create {title}")
        if not dry_run:
            sh("gh", "issue", "create", "--title", title, "--label", label, "--body", body)
    for key, iss in by_key.items():
        if key not in wanted:
            print(f"issue: close #{iss['number']} ({key})")
            if not dry_run:
                sh("gh", "issue", "close", str(iss["number"]), "--comment", "No longer detected by the daily scan.")


# ---------------------------------------------------------------- summary

def summarize(findings, new, persistent, fastlane, stats, cfg):
    sevname = lambda s: "critical" if s >= 9 else "high" if s >= 7 else "medium" if s >= 4 else "low"
    lines = [f"# Security scan {dt.date.today()}", ""]
    for e in stats.get("errors", []):
        lines.append(f"> **scanner unavailable**: {e}")
        lines.append("")
    lines.append(f"derivations: {stats['drvs']}, vulnix hits: {stats['vulnix']}, osv queries: {stats['osv_q']} (hits {stats['osv']}), "
                 f"ghsa repos: {stats['ghsa_repos']} (advisories {stats['ghsa']})")
    lines.append(f"baseline: {stats['baseline']} keys, new (not in baseline): {len(new)}, "
                 f"persistent >= {cfg['persist_days']}d: {len(persistent)}")
    lines.append("")
    if fastlane:
        lines.append("## nixpkgs channel HEAD already has a newer version (fast-lane candidates)")
        lines.append("")
        lines.append("| attribute | locked nixpkgs | channel HEAD |\n|---|---|---|")
        lines.extend(f"| {p} | {a} | {b} |" for p, a, b in fastlane)
        lines.append("")
    lines.append("## New findings (not in baseline)")
    lines.append("")
    if not new:
        lines.append("none")
    else:
        lines.append("| sev | source | package | ids | hosts |\n|---|---|---|---|---|")
        for f in sorted(new, key=lambda f: -f["severity"]):
            ids = ", ".join(f["ids"][:6]) + (" …" if len(f["ids"]) > 6 else "")
            lines.append(f"| {sevname(f['severity'])} {f['severity']:.1f} | {f['source']} | {f['pname']} {f['version']} | {ids} | {', '.join(f['hosts'][:3])} |")
    lines.append("")
    lines.append("<details><summary>All findings</summary>\n")
    lines.append("| sev | source | package | ids |\n|---|---|---|---|")
    for f in sorted(findings, key=lambda f: -f["severity"]):
        ids = ", ".join(f["ids"][:4]) + (" …" if len(f["ids"]) > 4 else "")
        lines.append(f"| {f['severity']:.1f} | {f['source']} | {f['pname']} {f['version']} | {ids} |")
    lines.append("\n</details>")
    return "\n".join(lines)


# ------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--closure", required=True)
    ap.add_argument("--lock", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--history", help="directory of earlier results (*.json) for the persistence rule")
    ap.add_argument("--summary")
    ap.add_argument("--issues", action="store_true", help="open/close GitHub issues for persistent new findings")
    ap.add_argument("--fastlane", action="store_true", help="dispatch the nixpkgs update when channel HEAD is ahead")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    cfg = load_config()
    closure = json.load(open(args.closure))
    lock = json.load(open(args.lock))
    merged = merge_closure(closure)
    stats = {"drvs": len(merged), "vulnix": 0, "osv": 0, "osv_q": 0, "ghsa": 0, "ghsa_repos": 0}
    findings = []
    errors = []
    if cfg["scanners"].get("vulnix", True):
        try:
            v = run_vulnix(merged, ROOT / "vulnix-whitelist.toml")
            stats["vulnix"] = len(v)
            findings += v
        except ScannerError as e:
            errors.append(str(e))
    if cfg["scanners"].get("osv", True):
        try:
            o, stats["osv_q"] = run_osv(merged, cfg.get("osv", {}).get("extra", []))
            stats["osv"] = len(o)
            findings += o
        except Exception as e:  # noqa: BLE001 - network
            errors.append(f"osv failed: {e}")
    if cfg["scanners"].get("ghsa", True):
        g, stats["ghsa_repos"] = run_ghsa(lock)
        stats["ghsa"] = len(g)
        findings += g
    stats["errors"] = errors

    baseline_path = ROOT / "baseline.json"
    baseline = set(json.load(open(baseline_path))["keys"]) if baseline_path.exists() else set()
    stats["baseline"] = len(baseline)
    new = [f for f in findings if f["key"] not in baseline]

    today = dt.date.today()
    first_seen = {}
    if args.history:
        for p in sorted(Path(args.history).glob("*.json")):
            try:
                day = dt.date.fromisoformat(p.stem[:10])
                for k in json.load(open(p)).get("keys", []):
                    first_seen.setdefault(k, day)
            except (ValueError, json.JSONDecodeError):
                continue
    persistent = [f for f in new if (today - first_seen.get(f["key"], today)).days >= cfg["persist_days"]]

    fastlane = []
    vulnix_pnames = sorted({f["pname"] for f in findings if f["source"] == "vulnix"})
    if vulnix_pnames and cfg.get("fastlane", {}).get("enabled", True):
        fastlane = fastlane_candidates(lock, vulnix_pnames)

    json.dump({"date": str(today), "keys": sorted(f["key"] for f in findings), "findings": findings,
               "new": sorted(f["key"] for f in new), "persistent": sorted(f["key"] for f in persistent),
               "fastlane": fastlane}, open(args.out, "w"), indent=1)
    summary = summarize(findings, new, persistent, fastlane, stats, cfg)
    if args.summary:
        Path(args.summary).write_text(summary)
    print(summary)

    if stats["errors"]:
        print("degraded run: not touching issues or dispatching updates", file=sys.stderr)
        return
    if args.issues:
        sync_issues(persistent, args.dry_run)
    if args.fastlane and fastlane and not args.dry_run:
        sh("gh", "workflow", "run", "weekly-update.yml", "-f", "scope=nixpkgs", check=False)


if __name__ == "__main__":
    main()
