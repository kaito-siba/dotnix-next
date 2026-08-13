#!/usr/bin/env python3
"""Fetch the herdr session snapshot and print a compact agent summary as JSON.

Output shape (single line):
  {"ok": true, "agents": [{"agent", "status", "project", "title",
                            "pane_id", "workspace", "focused"}]}
  {"ok": false, "error": "..."}   when herdr is unreachable
"""

import json
import os
import socket
import sys

SOCKET_PATH = os.environ.get(
    "HERDR_SOCKET_PATH",
    os.path.expanduser("~/.config/herdr/herdr.sock"),
)


def main():
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(3)
        client.connect(SOCKET_PATH)
        request = json.dumps(
            {"id": "vibe-island", "method": "session.snapshot", "params": {}}
        ) + "\n"
        client.sendall(request.encode())
        buf = b""
        while b"\n" not in buf:
            chunk = client.recv(65536)
            if not chunk:
                break
            buf += chunk
        client.close()
        snap = json.loads(buf.split(b"\n")[0])["result"]["snapshot"]
    except Exception as err:  # noqa: BLE001 - single-shot helper, report and exit
        print(json.dumps({"ok": False, "error": str(err)}))
        return

    focused = snap.get("focused_pane_id")
    agents = []
    for a in snap.get("agents", []):
        cwd = a.get("foreground_cwd") or a.get("cwd") or ""
        agents.append(
            {
                "agent": a.get("agent", ""),
                "status": a.get("agent_status", ""),
                "project": os.path.basename(cwd.rstrip("/")) if cwd else "",
                "title": a.get("terminal_title_stripped", ""),
                "pane_id": a.get("pane_id", ""),
                "workspace": a.get("workspace_id", ""),
                "focused": a.get("pane_id") == focused,
            }
        )
    print(json.dumps({"ok": True, "agents": agents}, ensure_ascii=False))


if __name__ == "__main__":
    main()
