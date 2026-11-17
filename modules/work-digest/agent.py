"""work-digest: a Slack sweep and a standup draft, kept by one host and read over HTTP.

Two scheduled jobs run headless Claude Code (`claude -p`) under the user's own login, with
the claude.ai Slack connector's read-only tools:

  sweep     finds asks and FYIs for me in DMs and @-mentions since the last sweep, and marks
            earlier asks resolved once I replied.
  standup   drafts "what did you accomplish?" for a working day from my pull requests and
            their commits (GitHub, so it does not matter which machine the work was done on),
            the Slack asks I handled, the day's task-notes summaries on this host, and my own
            Slack messages.

`serve` exposes the results to herdr-app's inbox mod on this and other machines. Peers are
allowed by tailnet node name (`tailscale whois`); loopback is always allowed.

Config (JSON file in $WORK_DIGEST_CONFIG):
  {"port": 8792, "allowed_nodes": ["node"], "sweep_model": "sonnet", "standup_model": "sonnet",
   "cutover_hour": 18}
State: $XDG_STATE_HOME/work-digest/{slack,standup}.json
API (JSON):
  GET  /state            {"slack": {...}, "standup": {...}}
  POST /slack/sweep      sweep now (starts work-digest-sweep.service)
  POST /slack/items      {"op": "tick" | "skip" | "untick" | "clear", "ids": [permalink]}
                         tick = handled, skip = set aside, clear = forget everything ticked
  POST /standup/write    write the draft now (starts work-digest-standup.service)
"""

import fcntl
import json
import os
import socket
import subprocess
import sys
import time
from contextlib import contextmanager
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CONFIG = json.load(open(os.environ["WORK_DIGEST_CONFIG"]))
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "work-digest"
TASK_NOTES = STATE.parent / "task-notes"
UNITS = {"sweep": "work-digest-sweep.service", "standup": "work-digest-standup.service"}
DAY = 86400 * 1000

SLACK_TOOLS = [
    "ToolSearch",
    "mcp__claude_ai_Slack__slack_search_public_and_private",
    "mcp__claude_ai_Slack__slack_search_public",
    "mcp__claude_ai_Slack__slack_read_channel",
    "mcp__claude_ai_Slack__slack_read_thread",
    "mcp__claude_ai_Slack__slack_read_user_profile",
    "mcp__claude_ai_Slack__slack_search_users",
]
# claude takes the permission mode from the user's settings, and auto mode may approve tools not listed above.
SLACK_WRITES = [
    "mcp__claude_ai_Slack__slack_send_message",
    "mcp__claude_ai_Slack__slack_send_message_draft",
    "mcp__claude_ai_Slack__slack_schedule_message",
    "mcp__claude_ai_Slack__slack_create_canvas",
    "mcp__claude_ai_Slack__slack_update_canvas",
]
SWEEP_SCHEMA = {
    "type": "object",
    "required": ["items", "resolved", "error", "connected"],
    "properties": {
        "me": {"type": "object", "properties": {"id": {"type": "string"}, "name": {"type": "string"}, "tz": {"type": "string"}}},
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["permalink", "kind", "from", "channel", "text", "urgent"],
                "properties": {
                    "permalink": {"type": "string"}, "kind": {"enum": ["ask", "fyi"]}, "from": {"type": "string"},
                    "channel": {"type": "string"}, "text": {"type": "string"}, "due": {"type": "string"},
                    "urgent": {"type": "boolean"},
                },
            },
        },
        "resolved": {"type": "array", "items": {"type": "string"}},
        "error": {"type": "string"},
        "connected": {"type": "boolean"},
    },
}
STANDUP_SCHEMA = {
    "type": "object",
    "required": ["bullets", "slackChecked", "note"],
    "properties": {"bullets": {"type": "array", "items": {"type": "string"}}, "slackChecked": {"type": "boolean"},
                   "note": {"type": "string"}},
}


def log(*args):
    print(*args, flush=True)


def now_ms():
    return int(time.time() * 1000)


def run(*cmd, timeout=60, cwd=None):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd)
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(cmd, 1, "", str(e))


def out_json(*cmd, default=None):
    r = run(*cmd)
    try:
        return json.loads(r.stdout) if r.returncode == 0 else default
    except ValueError:
        return default


# --- state -----------------------------------------------------------------------
# The server and the scheduled jobs are separate processes: every read-modify-write of a
# state file holds its lock.

@contextmanager
def state(name, empty):
    STATE.mkdir(parents=True, exist_ok=True)
    path = STATE / f"{name}.json"
    with open(STATE / f"{name}.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            data = {**empty(), **json.loads(path.read_text())}
        except (OSError, ValueError):
            data = empty()
        yield data
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2))
        tmp.replace(path)


def empty_slack():
    return {"me": None, "lastAt": 0, "items": [], "dismissed": [], "handled": [], "error": "", "connected": True}


def empty_standup():
    return {"day": None, "label": None, "bullets": [], "writtenAt": 0, "slackChecked": False, "note": "", "error": ""}


def claude(prompt, schema, model, tools, timeout):
    """One headless run; returns its structured output, or raises with what went wrong."""
    work = STATE / "work"  # an empty folder: no repository's CLAUDE.md or settings apply
    work.mkdir(parents=True, exist_ok=True)
    r = run("claude", "-p", prompt, "--model", model, "--tools", "ToolSearch", "--allowedTools", ",".join(tools),
            "--disallowedTools", ",".join(SLACK_WRITES), "--output-format", "json", "--json-schema", json.dumps(schema),
            "--no-session-persistence", "--max-budget-usd", "2", timeout=timeout, cwd=work)
    try:
        answer = json.loads(r.stdout)
    except ValueError:
        raise RuntimeError(((r.stderr or r.stdout).strip().splitlines() or ["claude gave no answer"])[-1][:200]) from None
    if not answer.get("structured_output"):
        raise RuntimeError(str(answer.get("result") or answer.get("subtype") or "no structured output")[:200])
    return answer["structured_output"]


# --- Slack sweep -----------------------------------------------------------------

def sweep_prompt(s, now):
    after = s["lastAt"] - 10 * 60 * 1000 if s["lastAt"] else now - DAY
    me = f"{s['me']['name']} ({s['me']['id']}), timezone {s['me'].get('tz', '?')}" if s["me"] else \
        "unknown yet: read my own profile first and return it as me"
    still_open = [f"- {i['permalink']} | {i['from']} in {i['channel']}: {i['text'][:100]}" for i in s["items"] if not i["ticked"]]
    iso = lambda ms: datetime.fromtimestamp(ms / 1000).astimezone().isoformat(timespec="minutes")
    return f"""You run one headless Slack sweep for me. Nobody reads a chat; your answer is the JSON. Load the Slack tools with ToolSearch first.
Me: {me}.
Now: {iso(now)}. Look at messages since {iso(after)}.

1. Look only at DMs and group DMs to me, and messages anywhere that @-mention me. Nothing else.
2. For each candidate, read its thread. Skip it if I already replied or someone else settled it.
3. kind "ask": needs my answer or action. due: the deadline in words if one is stated, else empty. urgent: true for a blocker, a deadline today, or a direct ask from my manager. kind "fyi": I should know, nothing to do. Leave out chatter, bots, and anything I wrote.
4. These are still open from earlier sweeps. Put a permalink in resolved when I have since replied or it no longer needs me:
{chr(10).join(still_open) or "(none)"}
Do not return those again as items unless something new happened in them.

text: the ask in one sentence, in the asker's words and language where possible, under 200 characters. channel: "#name", or "DM", or "group DM". from: the person's display name.
Read only: never post, reply, react, draft, schedule or change anything.
connected: false when no Slack tools are available or they say I need to sign in; then return empty lists.
If the Slack tools are there but keep failing, return empty lists and one short reason in error; otherwise error is ""."""


def log_handled(s, item, now):
    """Asks I handled (ticked, or replied to so a sweep resolved them), kept two weeks for the standup."""
    if item["kind"] != "ask":
        return
    s["handled"] = [h for h in s["handled"] if h["permalink"] != item["permalink"] and now - h["at"] < 14 * DAY]
    s["handled"].append({k: item.get(k) for k in ("permalink", "from", "channel", "text", "by")} | {"at": now})


def merge(s, out, now):
    if (out.get("me") or {}).get("id"):
        s["me"] = out["me"]
    known = {i["permalink"]: i for i in s["items"]}
    for item in out.get("items") or []:
        link = item.get("permalink")
        if not link or link in s["dismissed"]:
            continue
        if link in known:
            known[link].update(item)
        else:
            s["items"].append({**item, "at": now, "ticked": False, "tickedAt": None, "by": None})
    for link in out.get("resolved") or []:
        item = known.get(link)
        if item and not item["ticked"]:
            item.update(ticked=True, tickedAt=now, by="sweep")
            log_handled(s, item, now)
    # Ticked a week ago: forget it, and do not let a later sweep bring it back.
    s["dismissed"] += [i["permalink"] for i in s["items"] if i["ticked"] and now - i["tickedAt"] > 7 * DAY]
    s["items"] = [i for i in s["items"] if i["permalink"] not in s["dismissed"]]
    s["dismissed"] = s["dismissed"][-500:]
    s["lastAt"] = now


def sweep():
    with state("slack", empty_slack) as s:
        prompt = sweep_prompt(s, now_ms())
    try:
        out = claude(prompt, SWEEP_SCHEMA, CONFIG.get("sweep_model", "sonnet"), SLACK_TOOLS, 600)
    except (RuntimeError, OSError) as e:
        out = {"error": str(e), "connected": True}
    with state("slack", empty_slack) as s:
        s["error"], s["connected"] = out.get("error") or "", out.get("connected", True)
        # A failed or signed-out sweep keeps lastAt, so the next one looks at the same window again.
        if s["connected"] and not s["error"]:
            merge(s, out, now_ms())
    log(f"sweep: {len(out.get('items') or [])} items, {len(out.get('resolved') or [])} resolved, error={out.get('error')!r}, connected={out.get('connected')}")


def act(op, ids):
    now = now_ms()
    with state("slack", empty_slack) as s:
        for item in s["items"]:
            if item["permalink"] not in ids:
                continue
            if op == "tick":
                item.update(ticked=True, tickedAt=now, by="you")
                log_handled(s, item, now)
            elif op in ("skip", "untick"):
                item.update(ticked=op == "skip", tickedAt=now if op == "skip" else None, by="skipped" if op == "skip" else None)
                s["handled"] = [h for h in s["handled"] if h["permalink"] != item["permalink"]]
        if op == "clear":
            s["dismissed"] += [i["permalink"] for i in s["items"] if i["ticked"]]
            s["items"] = [i for i in s["items"] if not i["ticked"]]


# --- standup ---------------------------------------------------------------------

def window(now=None):
    """Before the cut-over hour: the previous working day (Friday on Monday). From it: today."""
    d = now or datetime.now().astimezone()
    if d.hour < CONFIG.get("cutover_hour", 18):
        d -= timedelta(days=1)
        while d.weekday() >= 5:
            d -= timedelta(days=1)
    start = d.replace(hour=0, minute=0, second=0, microsecond=0)
    return {"day": start.strftime("%Y-%m-%d"), "label": start.strftime("%A"),
            "from": int(start.timestamp() * 1000), "to": int((start + timedelta(days=1)).timestamp() * 1000) - 1}


def gather(win):
    """What I did that day, as plain lines for the prompt. Every source is optional."""
    inside = lambda ms: win["from"] <= ms <= win["to"]
    prs, commits = [], []
    authored = out_json("gh", "search", "prs", "--author=@me", f"--updated={win['day']}..{win['day']}", "--limit", "30",
                        "--json", "number,title,url,repository,state,isDraft", default=[])
    for p in authored:
        repo = (p.get("repository") or {}).get("name", "")
        prs.append(f"{repo} #{p['number']} {p['title']} ({'draft' if p.get('isDraft') else p['state'].lower()}) {p['url']}")
        # A branch's commits are not in GitHub's commit search; take them from the pull request.
        for c in (out_json("gh", "pr", "view", p["url"], "--json", "commits", default={}) or {}).get("commits", []):
            at = datetime.fromisoformat(c["committedDate"].replace("Z", "+00:00")).timestamp() * 1000
            if inside(at):
                commits.append(f"{repo} #{p['number']}: {c['messageHeadline']}")
    reviewed = out_json("gh", "search", "prs", "--reviewed-by=@me", f"--updated={win['day']}..{win['day']}", "--limit", "20",
                        "--json", "number,title,url,repository,author", default=[])
    mine = {p["url"] for p in authored}
    reviews = [f"{(p.get('repository') or {}).get('name', '')} #{p['number']} {p['title']} by {(p.get('author') or {}).get('login', '?')}"
               for p in reviewed if p["url"] not in mine]
    tasks = []
    for path in sorted(TASK_NOTES.glob("*.json")):
        try:
            t = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        if not inside(t.get("updatedAt", 0)):
            continue
        done = [x["text"] for x in t.get("steps", []) if x.get("state") == "done"][:5]
        tasks.append(f"{t.get('title')}: {t.get('goal')}" + (f" Done: {'; '.join(done)}" if done else ""))
    try:
        handled = json.loads((STATE / "slack.json").read_text()).get("handled", [])
    except (OSError, ValueError):
        handled = []
    slack = [f"{h['from']} ({h['channel']}) asked: \"{h['text']}\" ({'I replied in Slack' if h.get('by') == 'sweep' else 'I marked it done'})"
             for h in handled if inside(h["at"])]
    return {"commits": list(dict.fromkeys(commits))[:80], "prs": prs, "reviews": reviews, "tasks": tasks[:20], "slack": slack[:20]}


def standup_prompt(win, found):
    part = lambda title, lines: f"{title}:\n" + ("\n".join(f"- {x}" for x in lines) or "(none)")
    return f"""Write my standup answer to "What did you accomplish?" for {win['label']}, {win['day']}. Nobody reads a chat; your answer is the JSON.
First call ToolSearch for the Slack tools, even if neither ToolSearch nor any Slack tool is in your tool list: Slack connects after you start, and ToolSearch waits for it. Then look at the messages I sent that day (from:me, {win['day']} 00:00 to 23:59 my time), for work that did not leave a commit: reviews, debugging help, decisions. Read only: never post or change anything.

What I did that day:
{part("Commits", found["commits"])}

{part("Pull requests I opened or updated", found["prs"])}

{part("Pull requests I reviewed", found["reviews"])}

{part("Agent task summaries", found["tasks"])}

{part("Slack asks I handled", found["slack"])}

bullets: 3 to 7, one line each, outcome first, grouped by project where it helps. Name pull request numbers.
Merge the agent summaries with the commits instead of repeating them. Skip trivia (formatting, typo fixes, merges).
A Slack ask earns a bullet only when it was real work (a review, a fix, a decision, an unblock).
Write in the language my commits and messages are mostly in. Never invent work; with nothing to report, return no bullets.
slackChecked: true only when a Slack search for my messages ran and answered, even with no results.
note: one short sentence when something is missing from the draft, such as Slack not being searched; otherwise "". Write the bullets either way."""


def standup():
    win = window()
    try:
        out, error = claude(standup_prompt(win, gather(win)), STANDUP_SCHEMA, CONFIG.get("standup_model", "sonnet"), SLACK_TOOLS, 420), ""
    except (RuntimeError, OSError) as e:
        out, error = {}, str(e)
    with state("standup", empty_standup) as s:
        s["error"] = error
        if not error:
            checked = out.get("slackChecked") is True
            s.update(day=win["day"], label=win["label"], bullets=out.get("bullets") or [], writtenAt=now_ms(), slackChecked=checked,
                     note=out.get("note") or ("" if checked else "Slack was not checked"))
    log(f"standup {win['day']}: {len(out.get('bullets') or [])} bullets, slackChecked={out.get('slackChecked')}, note={out.get('note')!r}, error={error!r}")


# --- HTTP ------------------------------------------------------------------------

def running(job):
    return run("systemctl", "--user", "is-active", UNITS[job]).stdout.strip() in ("active", "activating")


def start(job):
    return run("systemctl", "--user", "start", "--no-block", UNITS[job]).returncode == 0


def snapshot():
    with state("slack", empty_slack) as s, state("standup", empty_standup) as d:
        today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).timestamp() * 1000
        return {
            "slack": {"items": [i for i in s["items"] if not i["ticked"] or i["tickedAt"] >= today], "lastAt": s["lastAt"],
                      "error": s["error"], "connected": s["connected"], "running": running("sweep")},
            "standup": {**d, "running": running("standup")},
        }


def allowed(ip):
    ip = ip.removeprefix("::ffff:")  # an IPv4 peer on the dual-stack socket
    if ip in ("127.0.0.1", "::1"):
        return True
    r = run("tailscale", "whois", "--json", ip)
    try:
        return json.loads(r.stdout)["Node"].get("ComputedName") in CONFIG["allowed_nodes"]
    except (ValueError, KeyError):
        return False


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def guard(self):
        if allowed(self.client_address[0]):
            return True
        self.reply(403, {"error": "this node is not allowed"})
        return False

    def do_GET(self):
        if not self.guard():
            return
        if self.path != "/state":
            return self.reply(404, {"error": "not found"})
        self.reply(200, snapshot())

    def do_POST(self):
        if not self.guard():
            return
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or "{}")
        except ValueError:
            return self.reply(400, {"error": "body is not JSON"})
        if self.path == "/slack/sweep":
            self.reply(202 if start("sweep") else 500, {"started": "sweep"})
        elif self.path == "/standup/write":
            self.reply(202 if start("standup") else 500, {"started": "standup"})
        elif self.path == "/slack/items":
            if body.get("op") not in ("tick", "skip", "untick", "clear"):
                return self.reply(400, {"error": "op must be tick, skip, untick or clear"})
            act(body["op"], set(body.get("ids") or []))
            self.reply(200, snapshot())
        else:
            self.reply(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        log(f"{self.client_address[0]} {fmt % args}")


class Server(ThreadingHTTPServer):
    # IPv6 with v4-mapped addresses too: tailnet peers may come over either.
    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "serve":
        log(f"work-digest on :{CONFIG['port']}, nodes: {sorted(CONFIG['allowed_nodes'])}")
        Server(("::", CONFIG["port"]), Handler).serve_forever()
    elif command == "sweep":
        sweep()
    elif command == "standup":
        standup()
    else:
        sys.exit("usage: agent.py serve | sweep | standup")


if __name__ == "__main__":
    main()
