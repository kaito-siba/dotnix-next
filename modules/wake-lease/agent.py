"""wake-lease: on-demand systemd services with leases, suspending the host when the work is done.

A client (allowed by its tailnet node name) that woke this host by Wake-on-LAN takes a
lease on a service, uses it, and releases the lease. A service's unit runs while it has
leases. When no lease is left on any service, the host is suspended only if the first
lease said the client woke it ("woke": true) and nobody has used the host since: no
keyboard/mouse input, no remote login session, no other GPU work, no sleep inhibitor in
block mode. Any sign of use cancels the suspend for this wake.

Config (JSON file in $WAKE_LEASE_CONFIG):
  {"port": 8089, "services": {"<service>": {"unit": "x.service", "health_url": "http://..." | null,
                                              "allowed_nodes": ["node"], "start_timeout": 300}}}
API (JSON):
  GET    /status
  POST   /lease/<service>           {"name": str, "woke": bool, "ttl": seconds}
                                    -> returns when the unit is up (health_url answers, if set)
  DELETE /lease/<service>/<name>
Leases expire after their ttl so a crashed client cannot keep the host awake.
"""

import glob
import json
import os
import struct
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONFIG = json.load(open(os.environ["WAKE_LEASE_CONFIG"]))
SERVICES = CONFIG["services"]
DEFAULT_TTL = 5400
SUSPEND_DELAY = 5  # let the release response reach the client first
GPU_WORK_MIB = 1024  # desktop apps (portal, Electron) hold small GPU contexts; only count real work

lock = threading.RLock()
leases = {}  # (service, name) -> {"expires": float, "woke": bool}
managed_since = None  # set while this wake was caused by a client and may end in suspend
last_input = 0.0


def log(*args):
    print(*args, flush=True)


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


# --- signs of use -------------------------------------------------------------------

def input_devices():
    """Event devices of keyboards and mice (udev ID_INPUT_KEYBOARD / ID_INPUT_MOUSE)."""
    out = []
    for path in glob.glob("/sys/class/input/event*/dev"):
        dev = open(path).read().strip()
        try:
            udev = open(f"/run/udev/data/c{dev}").read()
        except OSError:
            continue
        if "E:ID_INPUT_KEYBOARD=1" in udev or "E:ID_INPUT_MOUSE=1" in udev:
            out.append("/dev/input/" + path.split("/")[-2])
    return out


def watch_input():
    """Record the time of the last keyboard/mouse event (devices are rescanned for hotplug)."""
    watching = set()

    def reader(dev):
        global last_input
        size = struct.calcsize("llHHi")
        try:
            with open(dev, "rb") as f:
                while f.read(size):
                    last_input = time.time()
        except OSError:
            pass
        watching.discard(dev)

    while True:
        for dev in input_devices():
            if dev not in watching:
                watching.add(dev)
                threading.Thread(target=reader, args=(dev,), daemon=True).start()
        time.sleep(60)


def unit_pids():
    """PIDs belonging to the leased units (their own GPU use is not a sign of use)."""
    pids = set()
    for svc in SERVICES.values():
        group = run("systemctl", "show", "-p", "ControlGroup", "--value", svc["unit"]).stdout.strip()
        if group:
            try:
                pids |= set(open(f"/sys/fs/cgroup{group}/cgroup.procs").read().split())
            except OSError:
                pass
    return pids


def signs_of_use():
    """Reasons the host is in use by someone other than the lease clients (empty = idle)."""
    reasons = []
    if managed_since is not None and last_input > managed_since:
        reasons.append("keyboard/mouse input")
    for s in json.loads(run("loginctl", "list-sessions", "--json=short").stdout or "[]"):
        if run("loginctl", "show-session", s["session"], "-p", "Remote", "--value").stdout.strip() == "yes":
            reasons.append(f"remote session {s['session']} ({s.get('user')})")
    apps = run("nvidia-smi", "--query-compute-apps=pid,used_memory", "--format=csv,noheader,nounits").stdout
    own = unit_pids()
    gpu = [pid for pid, mem in (line.split(", ") for line in apps.splitlines())
           if int(mem) >= GPU_WORK_MIB and pid not in own]
    if gpu:
        reasons.append(f"GPU processes {','.join(gpu)}")
    inhibitors = run("busctl", "call", "--json=short", "org.freedesktop.login1", "/org/freedesktop/login1",
                     "org.freedesktop.login1.Manager", "ListInhibitors").stdout
    for what, who, why, mode, _uid, _pid in (json.loads(inhibitors)["data"][0] if inhibitors else []):
        if mode == "block" and "sleep" in what.split(":"):
            reasons.append(f"sleep inhibitor ({who}: {why})")
    return reasons


# --- leases ----------------------------------------------------------------------

def ready(svc):
    if not svc.get("health_url"):
        return run("systemctl", "is-active", "--quiet", svc["unit"]).returncode == 0
    try:
        with urllib.request.urlopen(svc["health_url"], timeout=3) as r:
            return r.status == 200
    except OSError:
        return False


def acquire(service, name, woke, ttl):
    global managed_since
    svc = SERVICES[service]
    with lock:
        if not leases:
            managed_since = time.time() if woke else None
        leases[(service, name)] = {"expires": time.time() + ttl, "woke": woke}
        log(f"lease {service}/{name} (woke={woke}, ttl={ttl}); managed={managed_since is not None}")
    run("systemctl", "start", "--no-block", svc["unit"])
    deadline = time.time() + svc.get("start_timeout", 300)
    while time.time() < deadline:
        if ready(svc):
            return True
        time.sleep(2)
    return False


def finish():
    """Called with the lock held after leases changed: stop idle units, maybe suspend."""
    global managed_since
    for service, svc in SERVICES.items():
        if not any(s == service for s, _ in leases):
            run("systemctl", "stop", svc["unit"])
    if leases:
        return
    if managed_since is None:
        log("no leases (host was not woken by a client)")
        return
    reasons = signs_of_use()
    managed_since = None
    if reasons:
        log("no leases; not suspending: " + "; ".join(reasons))
        return
    log(f"no leases; suspending in {SUSPEND_DELAY} s")
    threading.Timer(SUSPEND_DELAY, suspend_if_still_idle).start()


def suspend_if_still_idle():
    with lock:
        if leases:
            log("suspend cancelled: new lease")
            return
    run("systemctl", "suspend")


def release(service, name):
    with lock:
        existed = leases.pop((service, name), None) is not None
        log(f"release {service}/{name} ({'ok' if existed else 'unknown'})")
        finish()
    return existed


def sweep():
    """Expire leases; give up suspending as soon as the host is used during the work."""
    global managed_since
    while True:
        time.sleep(60)
        with lock:
            now = time.time()
            expired = [k for k, l in leases.items() if l["expires"] < now]
            for k in expired:
                del leases[k]
                log(f"lease {k[0]}/{k[1]} expired")
            if managed_since is not None and leases and (reasons := signs_of_use()):
                log("host in use, will not suspend: " + "; ".join(reasons))
                managed_since = None
            if expired:
                finish()


# --- HTTP ------------------------------------------------------------------------

def peer_node(ip):
    out = run("tailscale", "whois", "--json", ip)
    if out.returncode != 0:
        return None
    return json.loads(out.stdout)["Node"].get("ComputedName")


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def route(self):
        """(service, rest) of /lease/<service>[/<rest>] if the peer may use it, else None (replied)."""
        parts = self.path.strip("/").split("/", 2)
        if len(parts) < 2 or parts[0] != "lease" or parts[1] not in SERVICES:
            self.reply(404, {"error": "not found"})
            return None
        node = peer_node(self.client_address[0])
        if node not in SERVICES[parts[1]]["allowed_nodes"]:
            self.reply(403, {"error": f"node {node!r} may not use {parts[1]!r}"})
            return None
        return parts[1], parts[2] if len(parts) > 2 else None

    def do_GET(self):
        if self.path != "/status":
            return self.reply(404, {"error": "not found"})
        node = peer_node(self.client_address[0])
        if not any(node in svc["allowed_nodes"] for svc in SERVICES.values()):
            return self.reply(403, {"error": f"node {node!r} is not allowed"})
        with lock:
            body = {
                "leases": [{"service": s, "name": n, "woke": l["woke"],
                            "expires_in": round(l["expires"] - time.time())} for (s, n), l in leases.items()],
                "managed": managed_since is not None,
                "ready": {name: ready(svc) for name, svc in SERVICES.items()},
            }
        self.reply(200, body)

    def do_POST(self):
        if not (r := self.route()):
            return
        service, _ = r
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or "{}")
        name = str(body.get("name") or self.client_address[0])
        if not acquire(service, name, bool(body.get("woke")), int(body.get("ttl") or DEFAULT_TTL)):
            release(service, name)
            return self.reply(503, {"error": f"{service} did not become ready"})
        self.reply(200, {"service": service, "lease": name})

    def do_DELETE(self):
        if not (r := self.route()):
            return
        service, name = r
        if not name:
            return self.reply(404, {"error": "lease name missing"})
        self.reply(200 if release(service, name) else 404, {"service": service, "lease": name})

    def log_message(self, fmt, *args):
        log(f"{self.client_address[0]} {fmt % args}")


if __name__ == "__main__":
    threading.Thread(target=watch_input, daemon=True).start()
    threading.Thread(target=sweep, daemon=True).start()
    log(f"wake-lease on :{CONFIG['port']}, services: {sorted(SERVICES)}")
    ThreadingHTTPServer(("", CONFIG["port"]), Handler).serve_forever()
