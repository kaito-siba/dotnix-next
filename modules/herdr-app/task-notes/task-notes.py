"""herdr の tab ごとに、そこで動く Claude Code が何をしているかの要約を書く。

  task-notes hook        Claude Code の Stop hook。裏で summarize を始めて、すぐに返る
  task-notes summarize   その裏の仕事 (hook が起動する)

要約は $XDG_STATE_HOME/task-notes/<tab の id>.json に置き、herdr-app の tasks mod が読む。
ファイルを書き換えた turn の後にだけ、Haiku を 1 回走らせて前の要約を更新する。
herdr の端末の外 (HC_TERMINAL_ID が無い) では何もしない。
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
MODEL = "haiku"
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "task-notes"
# summarize の中で走らせる claude も Stop hook を呼ぶ。この印で自分を呼び直さない
GUARD = "TASK_NOTES_SUMMARY"

SCHEMA = {
    "type": "object",
    "required": ["goal", "steps", "decisions", "notDone"],
    "properties": {
        "goal": {"type": "string"},
        "planFile": {"type": "string"},
        "steps": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["state", "text"],
                "properties": {"state": {"enum": ["done", "now", "todo"]}, "text": {"type": "string"}},
            },
        },
        "decisions": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["kind", "text"],
                "properties": {"kind": {"enum": ["decision", "assumption", "you_said"]}, "text": {"type": "string"}},
            },
        },
        "notDone": {"type": "array", "items": {"type": "string"}},
    },
}

INSTRUCTIONS = """You keep a short summary of an AI coding agent's task, for the developer who reviews its work.
Update the previous summary with the latest turn. Return the whole summary:
- goal: one or two sentences.
- steps: the plan, at most 7, each done, now or todo.
- decisions: at most 8. kind decision = a choice the agent made; assumption = something it assumed without confirmation, worded so a reviewer knows what to check; you_said = the developer's own instruction or answer, briefly quoted.
- notDone: at most 5: skipped tests, TODOs, open questions, risks.
- planFile: the plan file's path if one was written, else empty.
Plain words, each item under 140 characters. Write in the language the developer writes in. Never invent."""


def run(cmd, cwd=None):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def read_json(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None


def write_atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    tmp.replace(path)


def where(terminal):
    """端末の居る tab。herdr-app が端末に付ける label (herdr.tab と、人が読む "space / tab") から取る。"""
    out = run(["hc", "get", terminal, "--json"])
    if not out:
        return None
    labels = json.loads(out).get("labels") or {}
    tab = labels.get("herdr.tab")
    return {"tab": tab, "title": labels.get("where") or tab} if tab else None


def last_turn(transcript):
    """人が最後に打った prompt から後の message。"""
    messages = []
    for line in Path(transcript).read_text().splitlines():
        try:
            o = json.loads(line)
        except ValueError:
            continue
        if o.get("type") in ("user", "assistant") and not o.get("isMeta") and o.get("message"):
            messages.append(o)

    def is_prompt(o):
        content = o["message"].get("content")
        return o["type"] == "user" and (isinstance(content, str) or any(c.get("type") == "text" for c in content))

    start = len(messages) - 1
    while start > 0 and not is_prompt(messages[start]):
        start -= 1
    return messages[max(start, 0):]


def digest(turn):
    out, edits, plans, commands = [], [], [], set()
    budget = 9000

    def add(s):
        nonlocal budget
        if budget > 0:
            out.append(s[:budget])
            budget -= len(s)

    for o in turn:
        content = o["message"].get("content")
        if isinstance(content, str):
            content = [{"type": "text", "text": content}]
        for c in content or []:
            kind = c.get("type")
            if kind == "text" and c.get("text", "").strip():
                person = o["type"] == "user"
                add(f"{'PERSON' if person else 'AGENT'}: {c['text'].strip()[:1500 if person else 700]}")
            elif kind == "tool_use":
                i = c.get("input") or {}
                path = i.get("file_path") or i.get("notebook_path")
                if c.get("name") in EDIT_TOOLS:
                    edits.append(path or "?")
                if path and "/.claude/plans/" in path:
                    plans.append(path)
                if c.get("name") == "ExitPlanMode" and i.get("plan"):
                    add(f"PLAN: {str(i['plan'])[:1500]}")
                what = i.get("command") or path or i.get("pattern") or i.get("description") or ""
                add(f"TOOL {c.get('name')}" + (f": {str(what)[:160]}" if what else ""))
                if c.get("name") == "Bash":
                    commands.add(c.get("id"))
            elif kind == "tool_result" and c.get("tool_use_id") in commands:
                # command の結果。通った test や check を「確認済み」と数えられるように
                body = c.get("content")
                text = body if isinstance(body, str) else "\n".join(x.get("text", "") for x in body or [])
                add(f"RESULT {'(failed)' if c.get('is_error') else '(ok)'}: {text.strip()[-240:]}")
    return "\n".join(out), edits, plans


def hook():
    terminal = os.environ.get("HC_TERMINAL_ID")
    if os.environ.get(GUARD) or not terminal:
        return
    h = json.loads(sys.stdin.read() or "{}")
    transcript = h.get("transcript_path")
    if not transcript or not os.path.exists(transcript):
        return
    if not digest(last_turn(transcript))[1]:
        return
    job = json.dumps({"transcript": transcript, "cwd": h.get("cwd") or os.getcwd(), "terminal": terminal})
    subprocess.Popen(
        [sys.executable, __file__, "summarize", job],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True, env={**os.environ, GUARD: "1"},
    )


def summarize(job):
    job = json.loads(job)
    at = where(job["terminal"])
    if not at:
        return
    out = STATE / f"{at['tab']}.json"
    lock = out.with_suffix(".lock")
    if lock.exists() and time.time() - lock.stat().st_mtime < 300:
        return
    write_atomic(lock, str(os.getpid()))
    try:
        prev = read_json(out)
        text, _edits, plans = digest(last_turn(job["transcript"]))
        kept = {k: prev.get(k) for k in ("goal", "planFile", "steps", "decisions", "notDone")} if prev else None
        prompt = "\n".join([
            INSTRUCTIONS,
            f"\nTask: {at['title']}",
            f"\nPrevious summary:\n{json.dumps(kept, ensure_ascii=False) if kept else '(none)'}",
            f"\nPlan files written this turn: {', '.join(plans) or 'none'}",
            f"\nLatest turn:\n{text}",
        ])
        # repository の CLAUDE.md や設定を読ませないよう、何も無い folder で走らせる
        work = STATE / "work"
        work.mkdir(parents=True, exist_ok=True)
        r = subprocess.run(
            ["claude", "-p", prompt, "--model", MODEL, "--tools", "", "--output-format", "json",
             "--json-schema", json.dumps(SCHEMA), "--no-session-persistence", "--max-budget-usd", "0.3"],
            cwd=work, capture_output=True, text=True, timeout=180, env={**os.environ, GUARD: "1"},
        )
        try:
            summary = json.loads(r.stdout)["structured_output"]
        except (ValueError, KeyError, TypeError):
            summary = None
        error = out.with_suffix(".error")
        if not summary:
            write_atomic(error, f"{r.returncode}\n{r.stdout}\n{r.stderr}")
            return
        error.unlink(missing_ok=True)
        write_atomic(out, json.dumps({
            **summary, "title": at["title"], "cwd": job["cwd"],
            "branch": run(["git", "branch", "--show-current"], job["cwd"]),
            "turns": (prev or {}).get("turns", 0) + 1, "updatedAt": int(time.time() * 1000),
        }, ensure_ascii=False, indent=2))
    finally:
        lock.unlink(missing_ok=True)


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "hook":
        # 何が起きても agent を止めない
        try:
            hook()
        except Exception:
            pass
    elif command == "summarize":
        summarize(sys.argv[2])
    else:
        print("usage: task-notes hook | summarize <job>")


if __name__ == "__main__":
    main()
