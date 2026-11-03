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

Findings are keyed per package+version+source (the fix is a version bump
either way), but whether something is new is judged per advisory id: a CVE
published later for an already-known version must not hide behind the
package key. security/baseline.json holds the id keys (see id_keys) from when
the scan was introduced; a finding is new if any of its ids is outside it, and
it then carries only those ids.

Issues (--issues): one per finding key. It is *opened* once one of its new ids
has been seen on every complete run for long enough (judged from --history):
at once for MAL-*, persist_days_critical for severity >= 9, persist_days for
the rest. It gets a comment when more ids turn up later; an open issue is *kept* as
long as its key has any new id today, and *closed* when it has none.
A run in which any scanner failed is incomplete: it is reported, saved with
complete=false, and neither opens nor closes anything, because "could not
look" must never read as "gone".

Usage:
  scan.py --closure closure.json --lock flake.lock --out results.json
          [--history DIR] [--summary FILE] [--issues] [--fastlane] [--dry-run]
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

import lockgraph

try:
    from cvss import CVSS3, CVSS4  # nixpkgs python3Packages.cvss, see modules/ci/security-shell.nix
except ImportError:  # label fallback only; the summary says so per finding
    CVSS3 = CVSS4 = None

ROOT = Path(__file__).resolve().parent.parent  # security/
REPO = ROOT.parent
VULNIX_ATTEMPTS = 3
VULNIX_RETRY_SECONDS = 300
OSV_BATCH = 500

PYPI_RE = re.compile(r"^python3(?:\.\d+)?-(?P<name>.+?)-(?P<ver>\d[^-]*)$")
CRATE_RE = re.compile(r"^(?:cargo-package-|crate-)(?P<name>.+?)-(?P<ver>\d[^-]*?)(?:\.tar\.gz)?$")
GH_OWNER_RE = re.compile(r'owner\s*=\s*"([^"]+)"\s*;\s*repo\s*=\s*"([^"]+)"', re.S)
GH_URL_RE = re.compile(r"github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/releases/download/")
SEVERITY_LABELS = {"CRITICAL": 9.5, "HIGH": 8.0, "MODERATE": 5.0, "MEDIUM": 5.0, "LOW": 2.0}


class ScannerError(Exception):
    """A scanner could not run to completion. The run is then incomplete."""


def sh(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True)


def load_config():
    with open(ROOT / "config.toml", "rb") as f:
        return tomllib.load(f)


def finding(source, pname, version, ids, severity, how, hosts, detail="", id_severity=None):
    return {
        "key": f"{source}:{pname}:{version}",
        "source": source,
        "pname": pname,
        "version": version,
        "ids": sorted(set(ids)),
        "severity": severity,
        "severity_how": how,
        "id_severity": dict(id_severity or {}),
        "hosts": sorted(set(hosts)),
        "detail": detail,
    }


def id_keys(f):
    """{id key: id} for a finding. A ghsa finding is already one advisory (its
    ids are the GHSA and its CVE alias), so its key is the only id key."""
    if f["source"] == "ghsa":
        return {f["key"]: f["ids"][0] if f["ids"] else f["key"]}
    return {f"{f['key']}:{i}": i for i in f["ids"]}


def merge_findings(findings):
    """One finding per key: ids and hosts unioned, the highest severity kept."""
    out = {}
    for f in findings:
        m = out.get(f["key"])
        if m is None:
            out[f["key"]] = dict(f)
            continue
        m["ids"] = sorted(set(m["ids"]) | set(f["ids"]))
        m["hosts"] = sorted(set(m["hosts"]) | set(f["hosts"]))
        for i, v in f["id_severity"].items():
            m["id_severity"][i] = max(v, m["id_severity"].get(i, 0.0))
        if f["severity"] > m["severity"]:
            m["severity"], m["severity_how"] = f["severity"], f["severity_how"]
        if len(f["detail"]) > len(m["detail"]):
            m["detail"] = f["detail"]
    return list(out.values())


# ---------------------------------------------------------------- closure

def merge_closure(closure):
    """host -> {drv -> info}  ==>  drv -> info + hosts"""
    merged = {}
    for host, drvs in closure.items():
        for path, info in drvs.items():
            merged.setdefault(path, dict(info, hosts=[]))["hosts"].append(host)
    return merged


# ----------------------------------------------------------------- vulnix

def run_vulnix(merged, whitelist):
    # vulnix's text --from-file silently loads nothing (its paths never reach
    # the store), so hand it the packages.json shape instead: name plus patch
    # file names, no .drv files needed. Dedupe on (name, patches).
    pkgs = {}
    for d in merged.values():
        key = (d["name"], tuple(d.get("patches", [])))
        pkgs.setdefault(key, {"name": d["name"], "patches": [os.path.basename(x) for x in key[1]]})
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump({str(i): v for i, v in enumerate(pkgs.values())}, f)
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
    out = []
    for item in json.loads(r.stdout or "[]"):
        scores = item.get("cvssv3_basescore") or {}
        hosts = [h for d in by_name.get(item["name"], []) for h in d["hosts"]]
        out.append(finding("vulnix", item["pname"], item["version"], item["affected_by"],
                           max(scores.values(), default=0.0), "nvd", hosts, id_severity=scores))
    return merge_findings(out)


# -------------------------------------------------------------------- osv

def osv_queries(merged, extra):
    queries = defaultdict(set)
    for d in merged.values():
        m = PYPI_RE.match(d["name"])
        if m:
            queries[("PyPI", m["name"], m["ver"])].update(d["hosts"])
            continue
        m = CRATE_RE.match(d["name"])
        if m:
            queries[("crates.io", m["name"], m["ver"])].update(d["hosts"])
    for e in extra:
        for d in merged.values():
            if d["pname"] == e["pname"] and d["version"]:
                queries[(e["ecosystem"], e["name"], d["version"])].update(d["hosts"])
    return queries


def osv_post(path, body):
    req = urllib.request.Request(f"https://api.osv.dev/v1/{path}", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.load(resp)


def osv_get(path):
    with urllib.request.urlopen(f"https://api.osv.dev/v1/{path}", timeout=60) as resp:
        return json.load(resp)


def osv_severity(det):
    """(score, how). OSV's severity[].score is a CVSS vector, computed with
    the cvss library when available (cvss4 / cvss3); otherwise the word in
    database_specific.severity (label); otherwise (0.0, none). `how` goes
    into the report so a fallback is visible, not silent."""
    for sv in det.get("severity") or []:
        vec = sv.get("score", "")
        try:
            if sv.get("type") == "CVSS_V4" and CVSS4 and vec.startswith("CVSS:4"):
                return float(CVSS4(vec).base_score), "cvss4"
            if sv.get("type") == "CVSS_V3" and CVSS3 and vec.startswith("CVSS:3"):
                return float(CVSS3(vec).scores()[0]), "cvss3"
        except Exception:  # noqa: BLE001 - malformed vector
            continue
    word = str((det.get("database_specific") or {}).get("severity") or "").upper()
    if word in SEVERITY_LABELS:
        return SEVERITY_LABELS[word], "label"
    return 0.0, "none"


def osv_vulns(keys):
    """{query key: [vuln ids]} following each query's own pagination."""
    hits = defaultdict(list)
    pending = {k: None for k in keys}  # key -> next_page_token
    while pending:
        chunk = list(pending)[:OSV_BATCH]
        body = {"queries": []}
        for eco, n, v in chunk:
            q = {"package": {"name": n, "ecosystem": eco}, "version": v}
            if pending[(eco, n, v)]:
                q["page_token"] = pending[(eco, n, v)]
            body["queries"].append(q)
        results = osv_post("querybatch", body).get("results", [])
        if len(results) != len(chunk):
            raise ScannerError(f"osv: {len(results)} results for {len(chunk)} queries")
        for key, res in zip(chunk, results):
            hits[key].extend(x["id"] for x in res.get("vulns") or [])
            token = res.get("next_page_token")
            if token:
                pending[key] = token
            else:
                del pending[key]
    return hits


def run_osv(merged, extra):
    queries = osv_queries(merged, extra)
    try:
        hits = osv_vulns(sorted(queries))
    except ScannerError:
        raise
    except Exception as e:  # noqa: BLE001 - network
        raise ScannerError(f"osv failed: {e}") from e
    out, detail_cache = [], {}
    for key, ids in hits.items():
        if not ids:
            continue
        eco, n, v = key
        sev, how, summaries, id_sev = 0.0, "none", [], {}
        for vid in sorted(set(ids)):
            if vid not in detail_cache:
                try:
                    detail_cache[vid] = osv_get(f"vulns/{vid}")
                except Exception as e:  # noqa: BLE001
                    raise ScannerError(f"osv detail {vid} failed: {e}") from e
            det = detail_cache[vid]
            score, score_how = osv_severity(det)
            id_sev[vid] = 10.0 if vid.startswith("MAL-") else score
            if score > sev or (score == sev and how == "none"):
                sev, how = score, score_how
            if det.get("summary"):
                summaries.append(f"{vid}: {det['summary']}")
        malicious = any(i.startswith("MAL-") for i in ids)
        out.append(finding("osv", f"{eco}/{n}", v, ids, 10.0 if malicious else sev,
                           "malicious" if malicious else how, queries[key],
                           ("MALICIOUS PACKAGE. " if malicious else "") + "\n".join(summaries)[:2000], id_sev))
    return merge_findings(out), len(queries)


# ------------------------------------------------------------------- ghsa

def github_repos(lock):
    repos = set()
    for node in lockgraph.walk(lock).values():
        orig = node.get("original") or {}
        if orig.get("type") == "github":
            repos.add((orig["owner"], orig["repo"]))
    for nix_file in (REPO / "modules").rglob("*.nix"):
        text = nix_file.read_text(errors="ignore")
        repos.update(GH_OWNER_RE.findall(text))
        repos.update(GH_URL_RE.findall(text))
    return sorted(repos)


def run_ghsa(lock):
    out = []
    repos = github_repos(lock)
    for owner, repo in repos:
        # --slurp wraps every page into one outer array.
        r = sh("gh", "api", "--paginate", "--slurp", f"repos/{owner}/{repo}/security-advisories?state=published&per_page=100", check=False)
        if r.returncode != 0:
            if "HTTP 404" in r.stderr:  # repository gone or private: nothing to list
                continue
            raise ScannerError(f"ghsa {owner}/{repo}: {r.stderr.strip().splitlines()[-1] if r.stderr.strip() else r.returncode}")
        advisories = [adv for page in json.loads(r.stdout or "[]") for adv in page]
        for adv in advisories:
            sev = {"critical": 9.5, "high": 8.0, "medium": 5.0, "low": 2.0}.get(adv.get("severity"), 0.0)
            out.append({
                "key": f"ghsa:{owner}/{repo}:{adv['ghsa_id']}",
                "source": "ghsa",
                "pname": f"{owner}/{repo}",
                "version": "",
                "ids": [x for x in (adv.get("ghsa_id"), adv.get("cve_id")) if x],
                "severity": sev,
                "severity_how": "label",
                "id_severity": {adv["ghsa_id"]: sev},
                "hosts": [],
                "detail": f"{adv.get('summary', '')} (published {adv.get('published_at', '')[:10]}) {adv.get('html_url', '')}",
            })
    return out, len(repos)


# --------------------------------------------------------------- fastlane

def attr_versions(ref, pnames):
    names = " ".join(json.dumps(p) for p in pnames)
    expr = (
        f'let p = (builtins.getFlake "{ref}").legacyPackages.x86_64-linux; '
        f'get = n: let r = builtins.tryEval (if builtins.hasAttr n p then (builtins.getAttr n p).version or "" else ""); '
        f'in if r.success then r.value else ""; '
        f'in builtins.listToAttrs (map (n: {{ name = n; value = get n; }}) [ {names} ])'
    )
    r = sh("nix", "--extra-experimental-features", "nix-command flakes", "--option", "allow-import-from-derivation", "false",
           "eval", "--json", "--impure", "--expr", expr, check=False)
    return json.loads(r.stdout) if r.returncode == 0 else {}


def fastlane_candidates(lock, pnames):
    """vulnix hits whose nixpkgs attribute already moved on the channel HEAD:
    the same attribute's version in the locked nixpkgs vs the channel HEAD,
    because derivation names carry suffixes and one pname spans several."""
    node = lockgraph.walk(lock)["nixpkgs"]
    orig, locked = node["original"], node["locked"]
    head_ref = f"github:{orig['owner']}/{orig['repo']}/{orig.get('ref', 'master')}"
    locked_ref = f"github:{locked['owner']}/{locked['repo']}/{locked['rev']}"
    head, cur = attr_versions(head_ref, pnames), attr_versions(locked_ref, pnames)
    return [(p, cur[p], head[p]) for p in pnames if cur.get(p) and head.get(p) and cur[p] != head[p]]


# ---------------------------------------------------------------- history

def load_history(history_dir):
    """{date: result} from earlier runs, the latest generated_at per date."""
    best = {}
    for p in sorted(Path(history_dir).rglob("*.json")):
        try:
            data = json.load(open(p))
            day = dt.date.fromisoformat(data["date"])
        except (ValueError, KeyError, json.JSONDecodeError, TypeError):
            continue
        if day not in best or data.get("generated_at", "") > best[day].get("generated_at", ""):
            best[day] = data
    return best


def persist_days_for(f, i, cfg):
    """How long id i of finding f must persist before it opens an issue.
    Waiting is for what the weekly update may fix; malware is not fixed by
    waiting, and a critical one should not wait for Saturday."""
    if i.startswith("MAL-"):
        return 0
    return cfg["persist_days_critical"] if f["id_severity"].get(i, 0.0) >= 9 else cfg["persist_days"]


def persistent_keys(today_keys, history, today):
    """Keys seen on every complete run from at least today_keys[key] days ago
    until today. A complete run without the key resets it; incomplete runs are
    ignored either way."""
    streak_start = {}
    days = sorted(d for d in history if d < today)
    for day in days:
        run = history[day]
        if not run.get("complete", True):
            continue
        present = set(run.get("keys", []))
        for k in list(streak_start):
            if k not in present:
                del streak_start[k]
        for k in present:
            streak_start.setdefault(k, day)
    for k in today_keys:
        streak_start.setdefault(k, today)
    return {k for k, days in today_keys.items() if (today - streak_start[k]).days >= days}


# ----------------------------------------------------------------- issues

def sync_issues(create, keep, dry_run):
    """Open an issue for each key in `create` that has none; close open issues
    whose key is not in `keep`. Both are finding dicts keyed by key."""
    label = "security"
    r = sh("gh", "issue", "list", "--label", label, "--state", "open", "--limit", "500", "--json", "number,title,body", check=False)
    if r.returncode != 0:
        raise ScannerError(f"gh issue list failed: {r.stderr.strip()}")
    by_key = {}
    for iss in json.loads(r.stdout or "[]"):
        m = re.search(r"<!-- key: (.*?) -->", iss.get("body") or "")
        if m:
            by_key[m.group(1)] = iss
    if not dry_run:
        sh("gh", "label", "create", label, "--color", "B60205", "--description", "automated security scan", "--force", check=False)
    for key, f in create.items():
        if key in by_key:
            m = re.search(r"^\*\*ids\*\*: (.*)$", by_key[key].get("body") or "", re.M)
            known = set(m.group(1).split(", ")) if m else set()
            added = [i for i in f["ids"] if i not in known]
            # The body's ids line is what is compared, so update it too or
            # every later run comments again.
            if added:
                print(f"issue: #{by_key[key]['number']} new ids {', '.join(added)}")
                if not dry_run:
                    body = re.sub(r"^\*\*ids\*\*: .*$", f"**ids**: {', '.join(sorted(known | set(added)))}",
                                  by_key[key]["body"], count=1, flags=re.M)
                    sh("gh", "issue", "edit", str(by_key[key]["number"]), "--body", body)
                    sh("gh", "issue", "comment", str(by_key[key]["number"]), "--body", f"New ids detected: {', '.join(added)}")
            continue
        title = f"[security] {f['pname']} {f['version']} ({f['source']})".strip()
        body = "\n".join([
            f"<!-- key: {key} -->",
            f"**source**: {f['source']}  ",
            f"**package**: {f['pname']} {f['version']}  ",
            f"**severity**: {f['severity']} ({f['severity_how']})  ",
            f"**hosts**: {', '.join(f['hosts']) or '-'}  ",
            f"**ids**: {', '.join(f['ids'])}",
            "",
            f["detail"],
            "",
            "Opened by the daily security scan after the finding persisted. It closes on its own once "
            "the finding disappears (version bump) or its ids are added to security/baseline.json or the "
            "vulnix whitelist.",
        ])
        print(f"issue: create {title}")
        if not dry_run:
            sh("gh", "issue", "create", "--title", title, "--label", label, "--body", body)
    for key, iss in by_key.items():
        if key not in keep:
            print(f"issue: close #{iss['number']} ({key})")
            if not dry_run:
                sh("gh", "issue", "close", str(iss["number"]), "--comment", "No longer detected by the daily scan.")


# ---------------------------------------------------------------- summary

def summarize(findings, new, persistent, fastlane, stats, cfg, complete):
    sevname = lambda s: "critical" if s >= 9 else "high" if s >= 7 else "medium" if s >= 4 else "low"  # noqa: E731
    lines = [f"# Security scan {dt.date.today()}", ""]
    if not complete:
        lines.append("> **incomplete run**: a scanner failed, so nothing below is treated as \"gone\" and no issue is opened or closed.")
        for e in stats["errors"]:
            lines.append(f"> - {e}")
        lines.append("")
    lines.append(f"derivations: {stats['drvs']}, vulnix hits: {stats['vulnix']}, osv queries: {stats['osv_q']} (hits {stats['osv']}), "
                 f"ghsa repos: {stats['ghsa_repos']} (advisories {stats['ghsa']})")
    lines.append(f"baseline: {stats['baseline']} ids, new (packages with ids not in baseline): {len(new)}, "
                 f"persistent (MAL 0d / critical {cfg['persist_days_critical']}d / other {cfg['persist_days']}d): {len(persistent)}, "
                 f"history days: {stats['history']}")
    lines.append("")
    lines.append("severity: nvd = NVD の CVSS v3、cvss3 / cvss4 = OSV のベクトルから計算、label = CRITICAL/HIGH/MODERATE/LOW の語からの代表値 (fallback)、none = 情報なし")
    lines.append("")
    if fastlane:
        lines += ["## nixpkgs channel HEAD already has a newer version (fast-lane candidates)", "",
                  "| attribute | locked nixpkgs | channel HEAD |\n|---|---|---|"]
        lines += [f"| {p} | {a} | {b} |" for p, a, b in fastlane]
        lines.append("")
    lines += ["## New findings (not in baseline)", ""]
    if not new:
        lines.append("none")
    else:
        lines.append("| sev | source | package | ids | hosts |\n|---|---|---|---|---|")
        for f in sorted(new, key=lambda f: -f["severity"]):
            ids = ", ".join(f["ids"][:6]) + (" …" if len(f["ids"]) > 6 else "")
            lines.append(f"| {sevname(f['severity'])} {f['severity']:.1f} ({f['severity_how']}) | {f['source']} | {f['pname']} {f['version']} | {ids} | {', '.join(f['hosts'][:3])} |")
    lines += ["", "<details><summary>All findings</summary>", "", "| sev | source | package | ids |\n|---|---|---|---|"]
    for f in sorted(findings, key=lambda f: -f["severity"]):
        ids = ", ".join(f["ids"][:4]) + (" …" if len(f["ids"]) > 4 else "")
        lines.append(f"| {f['severity']:.1f} ({f['severity_how']}) | {f['source']} | {f['pname']} {f['version']} | {ids} |")
    lines.append("\n</details>")
    return "\n".join(lines)


# ------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--closure", required=True)
    ap.add_argument("--lock", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--history", help="directory of earlier results (searched recursively)")
    ap.add_argument("--summary")
    ap.add_argument("--issues", action="store_true", help="open/close GitHub issues")
    ap.add_argument("--fastlane", action="store_true", help="dispatch the nixpkgs update when channel HEAD is ahead")
    ap.add_argument("--dry-run", action="store_true", help="no gh writes, no dispatch")
    args = ap.parse_args()

    cfg = load_config()
    closure = json.load(open(args.closure))
    lock = lockgraph.load(args.lock)
    merged = merge_closure(closure)
    stats = {"drvs": len(merged), "vulnix": 0, "osv": 0, "osv_q": 0, "ghsa": 0, "ghsa_repos": 0, "errors": [], "history": 0}
    findings = []
    for name, enabled, run in (
        ("vulnix", cfg["scanners"].get("vulnix", True), lambda: (run_vulnix(merged, ROOT / "vulnix-whitelist.toml"), None)),
        ("osv", cfg["scanners"].get("osv", True), lambda: run_osv(merged, cfg.get("osv", {}).get("extra", []))),
        ("ghsa", cfg["scanners"].get("ghsa", True), lambda: run_ghsa(lock)),
    ):
        if not enabled:
            continue
        try:
            got, count = run()
        except ScannerError as e:
            stats["errors"].append(str(e))
            continue
        stats[name] = len(got)
        if name == "osv":
            stats["osv_q"] = count
        if name == "ghsa":
            stats["ghsa_repos"] = count
        findings += got
    complete = not stats["errors"]

    baseline_path = ROOT / "baseline.json"
    # keys is {id key: why it is accepted}; only the keys matter here.
    baseline = set(json.load(open(baseline_path))["keys"]) if baseline_path.exists() else set()
    stats["baseline"] = len(baseline)
    new, new_ids = [], {}
    for f in findings:
        unknown = {k: i for k, i in id_keys(f).items() if k not in baseline}
        if unknown:
            ids = sorted(set(unknown.values()))
            new.append(dict(f, ids=ids, severity=max(f["id_severity"].get(i, 0.0) for i in ids)))
            new_ids[f["key"]] = {k: persist_days_for(f, i, cfg) for k, i in unknown.items()}

    today = dt.date.today()
    history = load_history(args.history) if args.history else {}
    stats["history"] = len(history)
    all_new = {k: d for u in new_ids.values() for k, d in u.items()}
    persistent_set = persistent_keys(all_new, history, today) if complete else set()
    persistent = [f for f in new if persistent_set & new_ids[f["key"]].keys()]

    fastlane = []
    vulnix_pnames = sorted({f["pname"] for f in findings if f["source"] == "vulnix"})
    if vulnix_pnames and cfg.get("fastlane", {}).get("enabled", True):
        fastlane = fastlane_candidates(lock, vulnix_pnames)

    result = {
        "date": str(today),
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "complete": complete,
        "errors": stats["errors"],
        "keys": sorted(k for f in findings for k in id_keys(f)),
        "findings": findings,
        "new": sorted(all_new),
        "persistent": sorted(persistent_set),
        "fastlane": fastlane,
    }
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    json.dump(result, open(args.out, "w"), indent=1)
    summary = summarize(findings, new, persistent, fastlane, stats, cfg, complete)
    if args.summary:
        Path(args.summary).write_text(summary)
    print(summary)

    if not complete:
        print("incomplete run: not touching issues or dispatching updates", file=sys.stderr)
        return
    if args.issues:
        sync_issues({f["key"]: f for f in persistent}, {f["key"] for f in new}, args.dry_run)
    if args.fastlane and fastlane and not args.dry_run:
        r = sh("gh", "workflow", "run", "weekly-update.yml", "-f", "scope=nixpkgs", check=False)
        if r.returncode != 0:
            raise SystemExit(f"fastlane dispatch failed: {r.stderr.strip()}")
        print("fastlane: dispatched weekly-update (scope=nixpkgs)")


if __name__ == "__main__":
    main()
