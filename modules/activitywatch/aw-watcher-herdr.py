#!/usr/bin/env python3
"""Report herdr pane focus and Claude Code agent activity to ActivityWatch.

Two buckets are written, because two different things are being measured:

  aw-watcher-herdr_<host>          the *human's* attention: the focused pane
                                   only, so events never overlap and can be
                                   intersected with the afk/window buckets.

  aw-watcher-claude-agents_<host>  the *agents'* activity, which is inherently
                                   parallel. Recording one event per session
                                   would produce overlapping events and inflate
                                   every total, so the aggregate state (how
                                   many are working, on which projects) is
                                   sampled instead.
"""

import json
import os
import socket
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

HERDR_SOCKET = os.environ.get(
    "HERDR_SOCKET_PATH",
    os.path.expanduser("~/.config/herdr/herdr.sock"),
)
AW_URL = os.environ.get("AW_URL", "http://127.0.0.1:5600").rstrip("/")
POLL_INTERVAL = float(os.environ.get("POLL_INTERVAL", "10"))
# Tolerate a couple of missed polls before an event is split in two.
PULSETIME = float(os.environ.get("PULSETIME", str(POLL_INTERVAL * 3)))

HOSTNAME = socket.gethostname()
FOCUS_BUCKET = f"aw-watcher-herdr_{HOSTNAME}"
AGENT_BUCKET = f"aw-watcher-claude-agents_{HOSTNAME}"

_last_complaint = {}


def complain(key, message):
    """Log a message only when the condition changes, to avoid log spam."""
    if _last_complaint.get(key) != message:
        _last_complaint[key] = message
        print(message, file=sys.stderr, flush=True)


def snapshot():
    """Fetch the live herdr session snapshot over its unix socket."""
    request = json.dumps(
        {"id": "aw-watcher-herdr", "method": "session.snapshot", "params": {}}
    ) + "\n"
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(3)
    try:
        client.connect(HERDR_SOCKET)
        client.sendall(request.encode())
        buf = b""
        while b"\n" not in buf:
            chunk = client.recv(65536)
            if not chunk:
                break
            buf += chunk
    finally:
        client.close()
    return json.loads(buf.split(b"\n")[0])["result"]["snapshot"]


def aw_post(path, payload):
    request = urllib.request.Request(
        f"{AW_URL}/api/0{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        return response.status


def create_buckets():
    for bucket_id, bucket_type in (
        (FOCUS_BUCKET, "herdr.pane.current"),
        (AGENT_BUCKET, "claude.agents"),
    ):
        try:
            aw_post(
                f"/buckets/{bucket_id}",
                {
                    "client": bucket_id,
                    "type": bucket_type,
                    "hostname": HOSTNAME,
                },
            )
        except urllib.error.HTTPError as err:
            # aw-server answers 304 when the bucket already exists.
            if err.code != 304:
                raise


def heartbeat(bucket_id, data):
    aw_post(
        f"/buckets/{bucket_id}/heartbeat?pulsetime={PULSETIME}",
        {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "duration": 0,
            "data": data,
        },
    )


def project_of(cwd):
    return os.path.basename(cwd.rstrip("/")) if cwd else ""


def focus_event(snap):
    """Data for the focused pane, or None when nothing is focused."""
    focused_id = snap.get("focused_pane_id")
    pane = next(
        (p for p in snap.get("panes", []) if p.get("pane_id") == focused_id),
        None,
    )
    if pane is None:
        return None

    workspace_id = pane.get("workspace_id", "")
    label = next(
        (
            w.get("label", "")
            for w in snap.get("workspaces", [])
            if w.get("workspace_id") == workspace_id
        ),
        "",
    )
    cwd = pane.get("foreground_cwd") or pane.get("cwd") or ""

    return {
        "pane_id": pane.get("pane_id", ""),
        "workspace": workspace_id,
        "workspace_label": label,
        "project": project_of(cwd),
        "cwd": cwd,
        # agent_status is deliberately left out: it flips on every turn and
        # would fragment the focus event into unusable slivers.
        "agent": pane.get("agent", ""),
        "session_id": (pane.get("agent_session") or {}).get("value", ""),
        "title": pane.get("terminal_title_stripped", ""),
    }


def agent_event(snap):
    """Aggregate agent state, so events in this bucket never overlap."""
    working = [
        a for a in snap.get("agents", []) if a.get("agent_status") == "working"
    ]
    projects = sorted(
        {project_of(a.get("foreground_cwd") or a.get("cwd") or "") for a in working}
        - {""}
    )
    return {
        "status": "working" if working else "idle",
        "working_count": len(working),
        "projects": ",".join(projects),
    }


def main():
    buckets_ready = False

    while True:
        try:
            if not buckets_ready:
                create_buckets()
                buckets_ready = True

            snap = snapshot()
            complain("herdr", "aw-watcher-herdr: connected to herdr")

            focus = focus_event(snap)
            if focus is not None:
                heartbeat(FOCUS_BUCKET, focus)
            heartbeat(AGENT_BUCKET, agent_event(snap))

            complain("aw", "aw-watcher-herdr: reporting to ActivityWatch")
        except (OSError, urllib.error.URLError) as err:
            # herdr not running, or aw-server restarting. Keep polling.
            complain("herdr", f"aw-watcher-herdr: unavailable ({err})")
            buckets_ready = False
        except Exception as err:  # noqa: BLE001 - never let the loop die
            complain("error", f"aw-watcher-herdr: unexpected error ({err})")

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
