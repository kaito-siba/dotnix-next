"""herdr の端末で動く Claude Code の session ごとに、何をしているかの記録を書く。

  task-notes hook        Claude Code の Stop hook。裏で summarize を始めて、すぐに返る
  task-notes summarize   その裏の仕事 (hook と watch が起動する)
  task-notes watch       sbx の sandbox の中の Claude Code の turn の終わりを、host で見張る
  task-notes where <t>   端末 t の agent が今居る folder を JSON で出す (herdr-app の mod が呼ぶ)

記録は $XDG_STATE_HOME/task-notes/<session id>.json に置き、herdr-app の tasks mod が読む。
turn のたびに Haiku を 1 回走らせて記録を足す。調べ物や相談だけの turn でも書く。
要約を毎回丸ごと書き直すと、直近の話に引っ張られて goal が動き、古い経緯が消えていく。
なので書き直すのは「今の状態」(steps と notDone) だけにし、goal は開発者が方針を変えた時
だけ履歴に足し、決定と経緯は追記だけにする。goal の拠り所に、session で開発者が言った
事を毎回全部渡す。
turn が続けて終わった時は、走っている要約が終わってから、溜まった分を 1 回でまとめて書く。
失敗は <session id>.error に残し、mod が出す。KEEP より長く書かれない session の file は消す。
herdr の端末の外 (HC_TERMINAL_ID が無い) では何もしない。
sandbox の中には task-notes も hc も Stop hook も無いので、そこの turn は watch が
host の hc events から見つけ、transcript を探して summarize に渡す。
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

MODEL = "haiku"
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "task-notes"
# STATE の *.json は tab の要約だけにし、cache は別の所に置く
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "task-notes"
# summarize の中で走らせる claude も Stop hook を呼ぶ。この印で自分を呼び直さない
GUARD = "TASK_NOTES_SUMMARY"
# Haiku に渡す turn の文の上限 (文字数)
BUDGET = 12000
# そのうち、agent の最後の発言 (報告) に使う分
REPORT = 3000
CUT = "[…]"
# 開発者がこの session で言った事を、Haiku に渡す上限 (文字数)
ASKS = 5000
# 記録に残す経緯の行数と、そのうち Haiku に見せる新しい方の行数
TIMELINE, RECENT = 200, 12
# これより長く書かれていない session の file は消す (秒)。閉じた session も、resume で戻る間は残す
KEEP = 14 * 86400
# Claude Code が transcript に残す session の名前の entry と、その値の key。端末の title にも同じ物を出す
TITLES = {"ai-title": "aiTitle", "custom-title": "customTitle"}
# session に名前が付くまで、Claude Code が端末に出す title
UNTITLED = "Claude Code"
# sbx ls は 0.5 秒ほどかかる。mod を開くたびに呼ばれるので、答えをこの秒数だけ覚えておく
SANDBOX_TTL = 600
# where が出す key
PLACE = ("cwd", "root", "branch", "source", "session")

DECISION = {
    "type": "object",
    "required": ["kind", "text"],
    "properties": {"kind": {"enum": ["decision", "assumption", "you_said"]}, "text": {"type": "string"}},
}

# Haiku が返すのは記録の差分。goal と決定と経緯の扱いは merge() が決める
SCHEMA = {
    "type": "object",
    "required": ["goal", "goalBecause", "steps", "added", "superseded", "notDone", "planFile", "log"],
    "properties": {
        "goal": {"type": "string"},
        "goalBecause": {"type": "string"},
        "steps": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["state", "text"],
                "properties": {"state": {"enum": ["done", "now", "todo"]}, "text": {"type": "string"}},
            },
        },
        "added": {"type": "array", "items": DECISION},
        "superseded": {"type": "array", "items": {"type": "integer"}},
        "notDone": {"type": "array", "items": {"type": "string"}},
        "planFile": {"type": "string"},
        "log": {"type": "string"},
    },
}

INSTRUCTIONS = """You keep the record of an AI coding agent's task, for the developer who reviews its work.
You get the record so far, everything the developer said earlier in this session, and the newest part of the conversation. Return:
- goal: what the developer wants out of this whole session, in one or two sentences. Return "" to keep the recorded goal.
  Write a goal only when there is none yet, or when the developer's own words change, widen or narrow what they want.
  The agent moving on to a sub-step, an investigation or a side question does not change the goal.
- goalBecause: with a goal that replaces a recorded one, the developer's words that changed it, briefly quoted. Else "".
- steps: the current plan, at most 7, each done, now or todo. The whole list as it stands now.
- added: decisions that appear in the newest part only. Never repeat recorded ones. kind decision = a choice the agent made;
  assumption = something it assumed without confirmation, worded so a reviewer knows what to check; you_said = the developer's own instruction or answer, briefly quoted.
- superseded: the numbers of recorded decisions that the newest part overturned or made untrue. Usually empty.
- notDone: at most 5, the whole list as it stands now: skipped tests, TODOs, open questions, risks.
- planFile: the plan file's path if one was written, else the recorded one, else "".
- log: one line on the newest part: what was done, found or decided.
Plain words, each item under 140 characters. Write in the language the developer writes in. Never invent.
The newest part is abridged: "[…]" marks where text was cut here. Cut text is not unfinished work."""


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
    # 同じ file を同時に書く process (where、summarize) と一時 file を取り合わないよう、pid を付ける
    tmp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
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
    cache = CACHE / "sandbox-projects.json"
    # 前の版は STATE に置いていた
    (STATE / "sandbox-projects.json").unlink(missing_ok=True)
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
        # 覚えるのは次の呼び出しに任せる
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


def load(transcript):
    """transcript の user と assistant の message。"""
    messages = []
    for line in Path(transcript).read_text().splitlines():
        try:
            o = json.loads(line)
        except ValueError:
            continue
        if o.get("type") in ("user", "assistant") and not o.get("isMeta") and o.get("message"):
            messages.append(o)
    return messages


def is_prompt(o):
    content = o["message"].get("content")
    return o["type"] == "user" and (isinstance(content, str) or any(c.get("type") == "text" for c in content or []))


def since(messages, through):
    """through (前に記録した最後の message の uuid) より後の message。through が無いか見つからなければ、最後の turn。"""
    at = next((n for n, o in enumerate(messages) if through and o.get("uuid") == through), None)
    if at is not None:
        return at + 1
    start = len(messages) - 1
    while start > 0 and not is_prompt(messages[start]):
        start -= 1
    return max(start, 0)


# Claude Code が user の entry に足す物。開発者の言葉ではない
INSERTED = ("<system-reminder>", "<command-", "<local-command", "[Request interrupted", "Caveat:")


def said(o):
    """開発者が打った文。無ければ空。"""
    if o["type"] != "user" or o.get("isCompactSummary"):
        return ""
    content = o["message"].get("content")
    parts = [content] if isinstance(content, str) else [c.get("text", "") for c in content or [] if c.get("type") == "text"]
    return "\n".join(p.strip() for p in parts if p.strip() and not p.lstrip().startswith(INSERTED))


def asks(messages):
    """開発者がこの session で言った事を古い順に。最初の発言と新しい方を残し、溢れたら間を落とす。"""
    told = [" ".join(t.split()) for o in messages if (t := said(o))]
    if not told:
        return "(nothing)"
    first, rest = clip(told[0], 1200), [clip(t, 400) for t in told[1:]]
    budget, kept = ASKS - len(first), []
    for text in reversed(rest):
        if len(text) > budget:
            break
        kept.append(text)
        budget -= len(text)
    kept.reverse()
    left = len(rest) - len(kept)
    return "\n".join(f"- {t}" for t in [first, *([f"{CUT} ({left} messages left out)"] if left else []), *kept])


def clip(text, limit):
    return text if len(text) <= limit else f"{text[:limit]} {CUT}"


def digest(turn, report=""):
    """turn を Haiku に渡す文にする。長い turn では、古い tool の記録から落とす。

    report は hook が受け取った agent の最後の発言。Stop hook が走る時、それが
    transcript にまだ書かれていない事があるので、無ければ足す。
    """
    # items は (kind, text)。person と agent は発言そのまま、tool は出す行
    items, plans, commands = [], [], set()
    for o in turn:
        content = o["message"].get("content")
        if isinstance(content, str):
            content = [{"type": "text", "text": content}]
        for c in content or []:
            kind = c.get("type")
            if kind == "text" and c.get("text", "").strip():
                if o["type"] == "user":
                    if text := said({**o, "message": {"content": [c]}}):
                        items.append(("person", text))
                else:
                    items.append(("agent", c["text"].strip()))
            elif kind == "tool_use":
                i = c.get("input") or {}
                path = i.get("file_path") or i.get("notebook_path")
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
    return "\n".join(lines[n] for n in sorted(lines)), plans


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
        "session": h.get("session_id") or Path(transcript).stem,
        # 引数で渡すので、digest が使う長さまでにしておく
        "report": (h.get("last_assistant_message") or "").strip()[:REPORT],
    })
    subprocess.Popen(
        [sys.executable, __file__, "summarize", job],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True, env={**os.environ, GUARD: "1"},
    )


def settle(transcript, quiet=3, limit=20):
    """transcript への書き込みが、呼んだ時から数えて quiet 秒止まるまで待つ (長くても limit 秒)。

    呼んだ時に止まっていても待つ: 最後の発言は、turn が終わってから書かれる事がある。
    """
    begin = time.time()
    while (now := time.time()) < begin + limit:
        try:
            idle = now - max(os.path.getmtime(transcript), begin)
        except OSError:
            return
        if idle >= quiet:
            return
        time.sleep(quiet - idle)


def record(prev):
    """Haiku に見せる、ここまでの記録。決定は生きている物だけを、1 からの番号で並べる。"""
    if not prev:
        return "(none yet)"
    goals = prev.get("goals") or []
    live = [d for d in prev.get("decisions") or [] if not d.get("superseded")]
    return "\n".join([
        f"Goal: {goals[-1]['text'] if goals else '(none)'}",
        *[f"Earlier goal (until turn {g['until']}): {g['text']}" for g in goals[:-1]],
        f"Steps: {json.dumps(prev.get('steps') or [], ensure_ascii=False)}",
        "Decisions:", *[f"{n}. [{d['kind']}] {d['text']}" for n, d in enumerate(live, 1)],
        f"Not done: {json.dumps(prev.get('notDone') or [], ensure_ascii=False)}",
        f"Plan file: {prev.get('planFile') or '(none)'}",
        "Recent log:", *[f"- turn {e['turn']}: {e['text']}" for e in (prev.get("timeline") or [])[-RECENT:]],
    ])


def merge(prev, got, turn, first_ask):
    """Haiku の返した差分を記録に重ねる。goal と決定と経緯は消さずに足していく。"""
    prev = prev or {}
    goals = [dict(g) for g in prev.get("goals") or []]
    goal = " ".join((got.get("goal") or "").split())
    if goal and (not goals or goal != goals[-1]["text"]):
        if goals:
            goals[-1]["until"] = turn - 1
        goals.append({"turn": turn, "text": goal, "because": (got.get("goalBecause") or "").strip() if goals else ""})
    elif not goals and first_ask:
        # 最初の記録で goal が返らなかったら、開発者の最初の発言で代える
        goals.append({"turn": turn, "text": clip(first_ask, 200), "because": ""})
    decisions = [dict(d) for d in prev.get("decisions") or []]
    live = [d for d in decisions if not d.get("superseded")]
    for n in set(got.get("superseded") or []):
        if 1 <= n <= len(live):
            live[n - 1]["superseded"] = turn
    decisions += [{"kind": d["kind"], "text": d["text"], "turn": turn} for d in got.get("added") or [] if d.get("text")]
    timeline = (prev.get("timeline") or []) + ([{"turn": turn, "at": int(time.time() * 1000), "text": got["log"]}] if got.get("log") else [])
    return {
        "goals": goals, "steps": got.get("steps") or [], "decisions": decisions,
        "notDone": got.get("notDone") or [], "planFile": got.get("planFile") or prev.get("planFile") or "",
        "timeline": timeline[-TIMELINE:],
    }


def failed(base, message, detail=""):
    write_atomic(base.with_suffix(".error"), json.dumps({"at": int(time.time() * 1000), "message": message, "detail": detail[-4000:]}, ensure_ascii=False))


def why(r):
    """claude -p が要約を返さなかった理由の 1 行。"""
    try:
        o = json.loads(r.stdout)
        if o.get("is_error") or o.get("subtype") != "success":
            return clip(str(o.get("result") or o.get("subtype") or "error"), 200)
        return "the summary had no structured output"
    except (ValueError, AttributeError):
        pass
    tail = (r.stderr or r.stdout or "").strip().splitlines()
    return clip(tail[-1], 200) if tail else f"claude exited with {r.returncode}"


def update(job, base):
    """job の session の、前に記録した所から後を記録に足す。"""
    transcript = job["transcript"]
    # turn が終わってから書かれる発言があるので、書き込みが止まるのを待ってから読む
    settle(transcript)
    messages = load(transcript)
    out = base.with_suffix(".json")
    prev = read_json(out)
    start = since(messages, (prev or {}).get("through"))
    if start >= len(messages):
        return
    text, plans = digest(messages[start:], job.get("report") or "")
    if not text.strip():
        return
    at = where(job["terminal"]) or {}
    prompt = "\n".join([
        INSTRUCTIONS,
        f"\nTask: {at.get('title') or Path(job.get('cwd') or '').name}",
        f"\nRecord so far:\n{record(prev)}",
        f"\nThe developer said earlier in this session (oldest first):\n{asks(messages[:start])}",
        f"\nPlan files written in the newest part: {', '.join(plans) or 'none'}",
        f"\nNewest part:\n{text}",
    ])
    # repository の CLAUDE.md や設定を読ませないよう、何も無い folder で走らせる
    work = STATE / "work"
    work.mkdir(parents=True, exist_ok=True)
    try:
        r = subprocess.run(
            ["claude", "-p", prompt, "--model", MODEL, "--tools", "", "--output-format", "json",
             "--json-schema", json.dumps(SCHEMA), "--no-session-persistence", "--max-budget-usd", "0.3"],
            cwd=work, capture_output=True, text=True, timeout=180, env={**os.environ, GUARD: "1"},
        )
    except subprocess.TimeoutExpired:
        failed(base, "claude did not answer in 180 seconds")
        return
    except OSError as e:
        failed(base, f"could not run claude: {e}")
        return
    try:
        got = json.loads(r.stdout)["structured_output"]
    except (ValueError, KeyError, TypeError):
        got = None
    if not got:
        failed(base, why(r), f"{r.returncode}\n{r.stdout}\n{r.stderr}")
        return
    base.with_suffix(".error").unlink(missing_ok=True)
    turn = (prev or {}).get("turns", 0) + 1
    first = next((t for o in messages if (t := said(o))), "")
    write_atomic(out, json.dumps({
        **merge(prev, got, turn, first),
        "session": base.name, "title": at.get("title"), "cwd": job.get("cwd"),
        "branch": run(["git", "branch", "--show-current"], job.get("cwd")) if job.get("cwd") else None,
        "turns": turn, "updatedAt": int(time.time() * 1000),
        # 次はこの後から読む。turn の終わりに書かれる発言がまだ無くても、次の turn と一緒に読める
        "through": messages[-1].get("uuid"),
    }, ensure_ascii=False, indent=2))


def take(pending):
    """溜まっている job を取る。取る間に来た job は、次に取る。"""
    taken = pending.with_suffix(".taken")
    try:
        pending.replace(taken)
    except FileNotFoundError:
        return None
    return read_json(taken)


def prune():
    """KEEP より長く書かれていない session の file を消す。"""
    edge = time.time() - KEEP
    for path in STATE.iterdir():
        try:
            if path.is_file() and path.stat().st_mtime < edge:
                path.unlink()
        except OSError:
            pass


def summarize(job):
    job = json.loads(job)
    if not job.get("transcript"):
        # watch から来た sbx の端末。sandbox の中の agent の最後の発言は hook から受け取れないが、
        # digest は report が空なら transcript の最後の発言を使う
        place = locate(job["terminal"])
        if place["source"] != "sbx" or not place.get("transcript") or not place.get("session"):
            return
        job.update(transcript=place["transcript"], cwd=place["cwd"], session=place["session"])
    base = STATE / (job.get("session") or Path(job["transcript"]).stem)
    STATE.mkdir(parents=True, exist_ok=True)
    pending = base.with_suffix(".pending")
    # 先に job を置いてから lock を試す。lock を持つ側は、手放した後に pending を見直すので、
    # 置いた job は必ずどちらかが拾う。続けて終わった turn は、溜まった分を 1 回でまとめて書く
    write_atomic(pending, json.dumps(job))
    with open(base.with_suffix(".lock"), "w") as lock:
        while pending.exists():
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return
            running = base.with_suffix(".running")
            try:
                while todo := take(pending):
                    running.touch()
                    try:
                        update(todo, base)
                    except Exception as e:
                        failed(base, f"{type(e).__name__}: {e}")
            finally:
                running.unlink(missing_ok=True)
                fcntl.flock(lock, fcntl.LOCK_UN)
    prune()


def watch():
    """hc events を追い、sbx の端末で Claude Code の turn が終わったら summarize を始める。

    host で動く Claude Code は Stop hook が summarize を始めるので、ここでは扱わない。
    hc events が切れたら (core の再起動など) 非 0 で終わり、service の再起動に任せる。
    """
    events = subprocess.Popen(["hc", "events", "--json"], stdout=subprocess.PIPE, text=True)
    terminals, jobs = {}, []
    for line in events.stdout:
        jobs = [j for j in jobs if j.poll() is None]
        try:
            o = json.loads(line)
        except ValueError:
            continue
        p = o.get("params") or {}
        # 最初の行と、追い付けなかった時に来る missed は、全ての端末の snapshot
        if "terminals" in o or o.get("method") == "missed":
            terminals = {t["address"]: t for t in (o if "terminals" in o else p).get("terminals") or []}
            continue
        if o.get("method") != "event":
            continue
        address, kind, data = p.get("terminal"), p.get("type"), p.get("data") or {}
        if kind in ("created", "restarted"):
            terminals[address] = data
        elif kind == "removed":
            terminals.pop(address, None)
        elif address not in terminals:
            continue
        elif kind == "foreground":
            terminals[address]["foreground"] = data
        elif kind in ("finished", "lost"):
            terminals[address].pop("foreground", None)
        elif kind == "status":
            t = terminals[address]
            was, now = (t.get("status") or {}).get("state"), data.get("status") or {}
            t["status"] = data.get("status")
            # done は人が見ていない間に終わった印で、見ると idle になる。working からの変化だけが turn の終わり
            # 他の machine の端末 ("<machine>/t7") は、その machine の watch が扱う
            if (was == "working" and now.get("state") in ("done", "idle") and now.get("app") == "claude-code"
                    and (t.get("foreground") or {}).get("name") == "sbx" and "/" not in address):
                # stderr は watch の物を引き継ぐ: summarize が落ちた理由を service の journal に残す
                jobs.append(subprocess.Popen(
                    [sys.executable, __file__, "summarize", json.dumps({"terminal": address})],
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                    start_new_session=True, env={**os.environ, GUARD: "1"},
                ))
    sys.exit(f"task-notes: hc events ended ({events.wait()})")


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
    elif command == "watch":
        watch()
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
        print("usage: task-notes hook | summarize <job> | watch | where <terminal>")


if __name__ == "__main__":
    main()
