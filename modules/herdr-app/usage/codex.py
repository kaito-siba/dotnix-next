"""Codex の利用上限を codex app-server に訊き、herdr-app の下端の bar (../mods/limit-status) が読む形で出す。

  {"at": 1763600000, "windows": [{"mins": 300, "used": 42, "resets_at": 1763610000}, ...]}

at と resets_at は unix 秒、used は 0〜100。codex が無い時と答えを取れない時は、何も出さずに 1 で終わる。
app-server は JSON-RPC を 1 行に 1 つずつ stdio で話す。initialize の前は他の method を受け付けない。
"""

import json
import shutil
import subprocess
import sys
import threading
import time

# app-server を起こしてから答えを待つ上限 (秒)。mod の exec の timeout より短くする
TIMEOUT = 20


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def windows(snapshot):
    found = []
    for key in ("primary", "secondary"):
        window = snapshot.get(key) if isinstance(snapshot, dict) else None
        if not isinstance(window, dict):
            continue
        used, mins, reset = window.get("usedPercent"), window.get("windowDurationMins"), window.get("resetsAt")
        if number(used) and number(mins) and number(reset):
            found.append({"mins": int(mins), "used": max(0, min(100, used)), "resets_at": int(reset)})
    return found


def ask(codex):
    proc = subprocess.Popen(
        [codex, "app-server"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    # 答えないまま止まったら殺す。stdout が閉じて、待っている readline が戻る
    timer = threading.Timer(TIMEOUT, proc.kill)
    timer.start()

    def send(message):
        proc.stdin.write(json.dumps(message) + "\n")
        proc.stdin.flush()

    def reply(request):
        for line in proc.stdout:
            try:
                message = json.loads(line)
            except ValueError:
                continue
            if isinstance(message, dict) and message.get("id") == request:
                return message.get("result")
        return None

    try:
        send({"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "herdr-usage", "title": None, "version": "1"}, "capabilities": None}})
        if reply(1) is None:
            return None
        send({"method": "initialized"})
        send({"id": 2, "method": "account/rateLimits/read", "params": {"excludeResetCreditDetails": True}})
        return reply(2)
    except OSError:
        return None
    finally:
        timer.cancel()
        # stdin を閉じると app-server は自分で終わる
        try:
            proc.stdin.close()
            proc.wait(timeout=3)
        except (OSError, subprocess.TimeoutExpired):
            proc.kill()
            proc.wait()


def main():
    codex = shutil.which("codex")
    result = ask(codex) if codex else None
    found = windows(result.get("rateLimits")) if isinstance(result, dict) else []
    if not found:
        return 1
    print(json.dumps({"at": int(time.time()), "windows": found}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
