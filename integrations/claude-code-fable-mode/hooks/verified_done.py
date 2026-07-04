#!/usr/bin/env python3
"""Stop hook: the verified-done gate.

Blocks ending the turn when code files were edited but no verification
command ran AFTER the last code edit. "Done means demonstrated" moves from
prose (which a model can forget) into the harness (which it cannot).

Bounded annoyance: when Claude continues because this hook blocked,
`stop_hook_active` is true on the next stop and we always allow it — the
gate fires at most once per stop attempt.
"""

import json
import re
import sys

EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}

# Files whose edits don't require a verification run.
NON_CODE = re.compile(
    r"(\.(md|markdown|txt|rst|adoc)$)|(/\.claude/lessons/)|(/memory/)|(/docs?/)",
    re.IGNORECASE,
)

# Commands that count as exercising the change: tests, type checks, builds,
# linters, or driving the behavior directly.
VERIFY = re.compile(
    r"\b(pytest|py\.test|python3? -m (pytest|unittest)|unittest|vitest|jest|"
    r"npm (test|run (test|build|check|lint|typecheck))|pnpm (test|build|check|lint)|"
    r"yarn (test|build|lint)|bun (test|run)|cargo (test|check|build|clippy|run)|"
    r"tsc\b|eslint|prettier --check|ruff\b|mypy|pyright|black --check|"
    r"go (test|build|vet|run)|deno (test|check|lint|run)|"
    r"make (test|check|lint|build)|mvn (test|verify|package)|gradle\w* (test|check|build)|"
    r"dotnet (test|build|run)|uv run|npx tsc|curl\b|http\b|pre-commit|"
    r"docker (build|compose up)|supabase (test|start)|psql\b)",
)


def iter_tool_uses(path: str):
    """Yield (tool_name, input_dict) for every tool_use in the transcript."""
    with open(path) as f:
        for line in f:
            line = line.strip()
            if '"tool_use"' not in line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            stack = [entry]
            while stack:
                node = stack.pop()
                if isinstance(node, dict):
                    if node.get("type") == "tool_use" and "name" in node:
                        yield node["name"], node.get("input") or {}
                    stack.extend(node.values())
                elif isinstance(node, list):
                    stack.extend(node)


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return

    if payload.get("stop_hook_active"):
        return

    transcript = payload.get("transcript_path")
    if not transcript:
        return

    # Escape valve independent of stop_hook_active: if this gate has already
    # fired twice this session (its reason text appears in the transcript),
    # allow the stop — never loop a session on an unmet gate.
    try:
        with open(transcript) as f:
            if f.read().count("Verified-done gate:") >= 2:
                return
    except Exception:
        return

    last_code_edit = None  # (index, file_path)
    edits = 0
    verified_after = True  # vacuously true until a code edit appears

    try:
        for i, (name, tool_input) in enumerate(iter_tool_uses(transcript)):
            if name in EDIT_TOOLS:
                fp = str(
                    tool_input.get("file_path") or tool_input.get("notebook_path") or ""
                )
                if fp and not NON_CODE.search(fp):
                    last_code_edit = (i, fp)
                    edits += 1
                    verified_after = False
            elif name == "Bash" and not verified_after:
                if VERIFY.search(str(tool_input.get("command") or "")):
                    verified_after = True
    except Exception:
        return  # unreadable transcript — never wedge the session

    if edits == 0 or verified_after:
        return

    reason = (
        f"Verified-done gate: {edits} code edit(s) this session and none "
        f"verified after the last one ({last_code_edit[1]}). Done means "
        "demonstrated — run the success-criteria command, tests, or build "
        "now and report the actual output. If verification is genuinely "
        "impossible here, write 'NOT VERIFIED:' plus the exact command "
        "someone must run, then finish."
    )
    print(json.dumps({"decision": "block", "reason": reason}))


if __name__ == "__main__":
    main()
    sys.exit(0)
