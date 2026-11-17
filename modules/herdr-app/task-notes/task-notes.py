"""herdr の tab ごとに、そこで動く Claude Code が何をしているかの要約を書く。

  task-notes hook        Claude Code の Stop hook。裏で summarize を始めて、すぐに返る
  task-notes summarize   その裏の仕事 (hook が起動する)
  task-notes where <t>   端末 t の agent が今居る folder を JSON で出す (herdr-app の mod が呼ぶ)

要約は $XDG_STATE_HOME/task-notes/<tab の id>.json に置き、herdr-app の tasks mod が読む。
最初の要約は、ファイルを書き換えた turn の後に作る。要約のある tab では、turn のたびに
Haiku を 1 回走らせて前の要約を更新する (会話や command だけの turn でも step は進む)。
herdr の端末の外 (HC_TERMINAL_ID が無い) では何もしない。
"""

import fcntl
import json
import os
import subprocess
import sys
import time
import unicodedata
from datetime import datetime
from pathlib import Path

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
MODEL = "haiku"
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "task-notes"
# summarize の中で走らせる claude も Stop hook を呼ぶ。この印で自分を呼び直さない
GUARD = "TASK_NOTES_SUMMARY"
# Haiku に渡す turn の文の上限 (文字数)
BUDGET = 12000
# そのうち、agent の最後の発言 (報告) に使う分
REPORT = 3000
CUT = "[…]"
# Claude Code が transcript に残す session の名前の entry と、その値の key。端末の title にも同じ物を出す
TITLES = {"ai-title": "aiTitle", "custom-title": "customTitle"}
# session に名前が付くまで、Claude Code が端末に出す title
UNTITLED = "Claude Code"
# sbx ls は 0.5 秒ほどかかる。mod を開くたびに呼ばれるので、答えをこの秒数だけ覚えておく
SANDBOX_TTL = 600
# where が出す key
PLACE = ("cwd", "root", "branch", "source", "session")

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
Plain words, each item under 140 characters. Write in the language the developer writes in. Never invent.
The latest turn is abridged: "[…]" marks where text was cut here. Cut text is not unfinished work."""


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


def clean(title):
    """agent が title の前に付ける状態の印 ("✳ ", "⠋ - ") を落とす。tasks mod の clean と同じ。"""
    title = title or ""
    at = 0
    while at < len(title) and not (title[at].isalnum() or unicodedata.category(title[at]) in ("Ps", "Pi")):
        at += 1
    return title[at:].strip()


def started(pid):
    """process が起動した時刻 (epoch 秒)。ps の etime は "[[dd-]hh:]mm:ss" の形。"""
    out = run(["ps", "-o", "etime=", "-p", str(pid)]) if pid else None
    if not out:
        return None
    days, _, clock = out.rpartition("-")
    try:
        seconds = 0
        for part in clock.split(":"):
            seconds = seconds * 60 + int(part)
        seconds += int(days or 0) * 86400
    except ValueError:
        return None
    return time.time() - seconds


def sandbox_projects():
    """sandbox の中の ~/.claude/projects を mount した、host の folder。"""
    cache = STATE / "sandbox-projects.json"
    try:
        if time.time() - cache.stat().st_mtime < SANDBOX_TTL:
            return json.loads(cache.read_text())
    except (OSError, ValueError):
        pass
    try:
        boxes = json.loads(run(["sbx", "ls", "--json"]) or "")
    except ValueError:
        return []
    # mount は "host の path:中の path" の形で、後ろに ":ro" が付く事がある
    dirs = sorted({m.split(":")[0] for box in boxes for m in box.get("mounts") or [] if m.split(":")[1:2] and m.split(":")[1].endswith("/.claude/projects")})
    try:
        write_atomic(cache, json.dumps(dirs))
    except OSError:
        # write_atomic の一時 file は名前が決まっているので、同時に走る where と取り合う事がある。覚えるのは次の呼び出しに任せる
        pass
    return dirs


def tail(transcript):
    """transcript の最後の user の entry と、最後の title の entry。末尾から読み、揃わなければ読む範囲を広げる。"""
    size = os.path.getsize(transcript)
    span = 1 << 16
    while True:
        with open(transcript, "rb") as f:
            f.seek(max(0, size - span))
            lines = f.read().splitlines()
        if span < size:
            # 途中から読んだので、最初の行は欠けている
            lines = lines[1:]
        found = {}
        for line in reversed(lines):
            for kind in ("user", *TITLES):
                if kind in found or f'"type":"{kind}"'.encode() not in line:
                    continue
                try:
                    o = json.loads(line)
                except ValueError:
                    continue
                if o.get("type") == kind:
                    found[kind] = o
        if span >= size or ("user" in found and found.keys() & TITLES.keys()):
            return found
        span *= 8


def begun(transcript):
    """transcript の最初の entry の時刻 (epoch 秒)。"""
    with open(transcript) as f:
        for line in f:
            try:
                stamp = json.loads(line).get("timestamp")
            except ValueError:
                continue
            if stamp:
                return datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
    return None


def sandbox_session(terminal, fg):
    """sbx の端末で動く Claude Code の transcript と、その最新の user の entry の cwd。

    sandbox の中の session は host の pid から引けない (中の sessions/ は sandbox の間で
    共有され、pid がぶつかる)。端末の title と、transcript に残る最後の title を突き合わせる。
    session に名前がまだ無い最初の turn は、sbx の起動より後に始まった title の無い transcript で代える。
    当てはまる session が 2 つ以上あれば、どれがこの端末の物か決められないので None を返す。
    EnterWorktree した session は transcript が worktree の名前の folder へ移る事があるので、
    folder は決め打ちしない。cwd は user の entry の物を使う: assistant の entry は、Bash の
    cd で一時だけ下の階層に揺れる事がある。
    """
    start, root, title = started(fg.get("pid")), fg.get("cwd") or "", clean(terminal.get("title"))
    # 順位ごとの、session id から (mtime, path, cwd)
    picks = {}
    for projects in sandbox_projects():
        for path in Path(projects).glob("*/*.jsonl"):
            try:
                mtime = path.stat().st_mtime
                if start and mtime < start:
                    continue
                found = tail(path)
                cwd = (found.get("user") or {}).get("cwd") or ""
                # sbx は workspace の root で動く。そこと上下の関係に無い folder の session は他の sandbox の物
                if not cwd or not (cwd == root or cwd.startswith(root + "/") or root.startswith(cwd + "/")):
                    continue
                titles = {clean(found[kind].get(key)) for kind, key in TITLES.items() if kind in found} - {""}
                if title in titles:
                    rank = 2
                elif title == UNTITLED and not titles and start and (begun(path) or 0) >= start:
                    rank = 1
                else:
                    continue
            except (OSError, ValueError):
                continue
            same = picks.setdefault(rank, {})
            if path.stem not in same or mtime > same[path.stem][0]:
                same[path.stem] = (mtime, path, cwd)
    top = picks[max(picks)] if picks else {}
    if len(top) != 1:
        return None
    _, path, cwd = next(iter(top.values()))
    return {"cwd": cwd, "session": path.stem, "transcript": str(path)}


def locate(terminal, place=None):
    """端末の agent が今居る folder と、そこの git の toplevel と branch。

    hc の cwd は端末を作った時の folder のままなので、foreground の process の cwd を見る。
    Claude Code が EnterWorktree すると、host の process の cwd は worktree へ移る。sbx の
    process の cwd は workspace の root から動かないので、sandbox の中の agent は transcript で見る。
    調べる途中で例外が出ても、place には調べ終えた所までが入っている。
    """
    if place is None:
        place = dict.fromkeys(PLACE)
    out = run(["hc", "get", terminal, "--json"])
    if not out:
        return place
    t = json.loads(out)
    fg = t.get("foreground") or {}
    place.update(cwd=fg.get("cwd") or t.get("cwd"), source="pane")
    # nix で入れた claude は ".claude-wrapped" という名前で動く
    if "claude" in (fg.get("name") or "") or os.path.basename((fg.get("argv") or [""])[0]) == "claude":
        sessions = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude") / "sessions"
        place.update(source="claude", session=(read_json(sessions / f"{fg.get('pid')}.json") or {}).get("sessionId"))
    elif fg.get("name") == "sbx":
        place["source"] = "sbx"
        place.update(sandbox_session(t, fg) or {})
    if place["cwd"]:
        place["root"] = run(["git", "rev-parse", "--show-toplevel"], place["cwd"]) or None
        place["branch"] = place["root"] and (run(["git", "branch", "--show-current"], place["cwd"]) or None)
    return place


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


def clip(text, limit):
    return text if len(text) <= limit else f"{text[:limit]} {CUT}"


def digest(turn, report=""):
    """turn を Haiku に渡す文にする。長い turn では、古い tool の記録から落とす。

    report は hook が受け取った agent の最後の発言。Stop hook が走る時、それが
    transcript にまだ書かれていない事があるので、無ければ足す。
    """
    # items は (kind, text)。person と agent は発言そのまま、tool は出す行
    items, edits, plans, commands = [], [], [], set()
    for o in turn:
        content = o["message"].get("content")
        if isinstance(content, str):
            content = [{"type": "text", "text": content}]
        for c in content or []:
            kind = c.get("type")
            if kind == "text" and c.get("text", "").strip():
                items.append(("person" if o["type"] == "user" else "agent", c["text"].strip()))
            elif kind == "tool_use":
                i = c.get("input") or {}
                path = i.get("file_path") or i.get("notebook_path")
                if c.get("name") in EDIT_TOOLS:
                    edits.append(path or "?")
                if path and "/.claude/plans/" in path:
                    plans.append(path)
                if c.get("name") == "ExitPlanMode" and i.get("plan"):
                    items.append(("tool", f"PLAN: {clip(str(i['plan']), 1500)}"))
                what = i.get("command") or path or i.get("pattern") or i.get("description") or ""
                items.append(("tool", f"TOOL {c.get('name')}" + (f": {str(what)[:160]}" if what else "")))
                if c.get("name") == "Bash":
                    commands.add(c.get("id"))
            elif kind == "tool_result" and c.get("tool_use_id") in commands:
                # command の結果。通った test や check を「確認済み」と数えられるように
                body = c.get("content")
                text = body if isinstance(body, str) else "\n".join(x.get("text", "") for x in body or [])
                # 末尾だけを取る。切った印は付けない: 付けると「出力が途中で切れた」と要約される
                items.append(("tool", f"RESULT {'(failed)' if c.get('is_error') else '(ok)'}: {text.strip()[-240:]}"))
    if report and not any(kind == "agent" and text.startswith(report) for kind, text in items):
        items.append(("agent", report))

    def line(n, limit):
        kind, text = items[n]
        return text if kind == "tool" else f"{kind.upper()}: {clip(text, limit)}"

    # 人の発言と agent の最後の発言 (報告) を先に取り、残りの枠を新しい方から埋める。
    # 先頭から埋めると、長い turn では結論の書いてある最後の報告が落ちる
    last = max((n for n, (kind, _) in enumerate(items) if kind == "agent"), default=None)
    lines = {n: line(n, 1500 if kind == "person" else REPORT) for n, (kind, _) in enumerate(items) if kind == "person" or n == last}
    budget = BUDGET - sum(map(len, lines.values()))
    for n in reversed(range(len(items))):
        if n in lines:
            continue
        if len(line(n, 700)) > budget:
            lines[n] = f"{CUT} (earlier entries left out)"
            break
        lines[n] = line(n, 700)
        budget -= len(lines[n])
    return "\n".join(lines[n] for n in sorted(lines)), edits, plans


def hook():
    terminal = os.environ.get("HC_TERMINAL_ID")
    if os.environ.get(GUARD) or not terminal:
        return
    h = json.loads(sys.stdin.read() or "{}")
    transcript = h.get("transcript_path")
    if not transcript or not os.path.exists(transcript):
        return
    # 要約するかは裏で決める: transcript を読むのも、tab を調べるのも時間がかかる
    job = json.dumps({
        "transcript": transcript, "cwd": h.get("cwd") or os.getcwd(), "terminal": terminal,
        # 引数で渡すので、digest が使う長さまでにしておく
        "report": (h.get("last_assistant_message") or "").strip()[:REPORT],
    })
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
    # 待つ前に読む: 待っている間に次の turn が始まると、最後の turn が入れ替わる
    text, edits, plans = digest(last_turn(job["transcript"]), job.get("report") or "")
    # 前の turn の要約がまだ走っていたら、終わるのを待つ。飛ばすと、すぐ後に
    # 終わった turn (短い返事など) が要約に入らない
    STATE.mkdir(parents=True, exist_ok=True)
    with open(out.with_suffix(".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        prev = read_json(out)
        if not prev and not edits:
            return
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
    elif command == "where" and len(sys.argv) > 2:
        # mod はこれが失敗すると pane の folder に落ちる。調べ終えた所までを、いつも JSON で返す
        place = dict.fromkeys(PLACE)
        try:
            locate(sys.argv[2], place)
        except Exception:
            pass
        place.pop("transcript", None)
        print(json.dumps(place, ensure_ascii=False))
    else:
        print("usage: task-notes hook | summarize <job> | where <terminal>")


if __name__ == "__main__":
    main()
