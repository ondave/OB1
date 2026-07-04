#!/usr/bin/env python3
"""SessionStart hook: inject discipline invariants + lessons for this repo.

Retrieval happens mechanically here so the model never has to remember to
ask its memory. Sources, both best-effort:
  1. Open Brain `list_lessons` (repo-scoped + global) via the open-brain MCP
     endpoint configured in ~/.claude.json — no secrets stored in this repo.
  2. `.claude/lessons/*.md` files in the current repo (newest few).

This script must never break a session: on any failure it degrades to the
invariants block alone, and always exits 0.
"""

import json
import os
import re
import subprocess
import sys
import urllib.request

MAX_LESSONS = 5
MAX_REPO_FILES = 3
TIMEOUT_S = 5

INVARIANTS = """\
## Operating invariants (fable-mode)

- Done means demonstrated: no completion claim without a verification
  command run in this session after the last edit (a Stop gate checks the
  transcript for this). If verification is impossible, say "NOT VERIFIED:"
  plus the exact command.
- Root cause before patch: reproduce, localize to file:line, explain the
  cause in one sentence — only then fix. Never patch the symptom.
- Minimal diff: every changed line traces to the ask; no drive-by cleanup.
- Finish the turn: never end on "I'll now..." — do it, or state plainly that
  you are stopping and why.
- Report outcome first: first sentence says what changed and whether it is
  verified; evidence (real command output) follows.
- For non-trivial coding tasks, use the fable-discipline skill; for review,
  spawn fresh-eyes-reviewer; when surprised, capture via /lesson."""


def repo_slug(cwd: str) -> str:
    try:
        root = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_S,
        ).stdout.strip()
        if root:
            return os.path.basename(root)
    except Exception:
        pass
    return os.path.basename(os.path.abspath(cwd))


def git_root(cwd: str) -> str | None:
    try:
        root = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_S,
        ).stdout.strip()
        return root or None
    except Exception:
        return None


def openbrain_lessons(repo: str) -> str:
    """Fetch active lessons (repo + global) from the open-brain MCP endpoint."""
    cfg_path = os.path.expanduser("~/.claude.json")
    with open(cfg_path) as f:
        server = json.load(f)["mcpServers"]["open-brain"]
    url = server["url"]
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    headers.update(server.get("headers", {}))

    body = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": {
                "name": "list_lessons",
                "arguments": {"repo": repo, "limit": MAX_LESSONS},
            },
        }
    ).encode()
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    raw = urllib.request.urlopen(req, timeout=TIMEOUT_S).read().decode()

    # Response may be plain JSON or an SSE stream of `data: {...}` lines.
    payloads = []
    if raw.lstrip().startswith("{"):
        payloads = [raw]
    else:
        payloads = [ln[5:].strip() for ln in raw.splitlines() if ln.startswith("data:")]
    for p in payloads:
        try:
            msg = json.loads(p)
        except json.JSONDecodeError:
            continue
        content = (msg.get("result") or {}).get("content") or []
        for c in content:
            if c.get("type") == "text":
                text = c["text"]
                return "" if text.startswith("No lessons") else text
    return ""


def repo_file_lessons(cwd: str) -> str:
    root = git_root(cwd)
    if not root:
        return ""
    ldir = os.path.join(root, ".claude", "lessons")
    if not os.path.isdir(ldir):
        return ""
    files = sorted((f for f in os.listdir(ldir) if f.endswith(".md")), reverse=True)[
        :MAX_REPO_FILES
    ]
    chunks = []
    for name in files:
        try:
            with open(os.path.join(ldir, name)) as f:
                text = f.read().strip()
            chunks.append(f"[{name}]\n{text[:800]}")
        except Exception:
            continue
    return "\n\n".join(chunks)


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}
    cwd = payload.get("cwd") or os.getcwd()
    repo = repo_slug(cwd)

    sections = [INVARIANTS]

    try:
        ob = openbrain_lessons(repo)
    except Exception:
        ob = ""
    if ob:
        sections.append(
            f"## Lessons from previous sessions (Open Brain, repo:{repo} + global)\n"
            f"Consult these before repeating a known mistake.\n\n{ob}"
        )

    try:
        rf = repo_file_lessons(cwd)
    except Exception:
        rf = ""
    if rf:
        sections.append(f"## Repo lessons (.claude/lessons/)\n\n{rf}")

    out = {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": "\n\n".join(sections),
        }
    }
    print(json.dumps(out))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # never break a session
    sys.exit(0)
