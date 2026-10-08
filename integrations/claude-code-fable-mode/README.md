# Claude Code Fable Mode

> Make a weaker model work like a stronger one by moving the discipline into the harness: hooks do the remembering and the gating, so the model doesn't have to.

## What It Does

Markdown disciplines fail on exactly the models that need them — instruction retention over long contexts is the weak faculty you'd be leaning on. This plugin keeps the prose thin and puts the checkpoints where they cannot be forgotten:

| Piece | Mechanism | What it replaces |
| --- | --- | --- |
| `hooks/inject_lessons.py` | **SessionStart hook** — injects operating invariants + the current repo's lessons (Open Brain `list_lessons`, repo + global) + `.claude/lessons/*.md` files + the nightly dream digest when it has news or has gone stale (`~/.local/state/openbrain/dream/digest.txt`, written by `ops/ob-dream-review.py`) | Hoping the model remembers to consult its memory |
| `hooks/verified_done.py` | **Stop hook** — blocks ending the turn when code was edited but nothing verified it afterwards | Hoping "done means demonstrated" survives 100k tokens |
| `agents/fresh-eyes-reviewer.md` | Fresh-context subagent that adversarially re-verifies a "done" claim | Self-review with the same blind spots that wrote the bug |
| `commands/lesson.md` | `/lesson` — capture atomic context→mistake→rule entries, routed by scope (repo file vs Open Brain) | Session diaries and unroutable notes |

Lessons routing follows the [lessons-ledger schema](../../schemas/lessons-ledger/): repo-specific truths live as files in the repo (reviewed in MRs, free for CI), cross-project and preference lessons live in Open Brain where semantic search can find them from any repo.

## Prerequisites

- Working Open Brain setup with the [lessons-ledger schema](../../schemas/lessons-ledger/) applied and the `store_lesson`/`search_lessons`/`list_lessons`/`retire_lessons` MCP tools registered.
- An `open-brain` MCP server entry in `~/.claude.json` (the SessionStart hook reads its URL and access key from there — no credentials live in this plugin).
- Claude Code ≥ 2.1.142, `python3` on PATH.

## Install (skills-directory plugin — no marketplace needed)

Symlink the plugin into your personal skills directory; Claude Code discovers any folder there containing `.claude-plugin/plugin.json` as a plugin, loaded in place:

```bash
ln -s /path/to/OB1/integrations/claude-code-fable-mode ~/.claude/skills/fable-mode
```

Restart Claude Code (or `/reload-plugins`). Verify with `claude plugin list` — you should see `fable-mode@skills-dir`. Disable anytime with `claude plugin disable fable-mode@skills-dir`.

## How the pieces behave

- **SessionStart** adds one short context block. If Open Brain is down or unconfigured it degrades silently to the invariants alone — it never breaks a session.
- **Stop gate** only fires when a *code* file was edited (docs/markdown/lessons are exempt) and no test/build/check/exercise command ran after the last edit. It blocks at most once (`stop_hook_active`), with a transcript-based escape valve as a second bound. The correct response to it is to run the verification — or state `NOT VERIFIED:` with the exact command.
- **fresh-eyes-reviewer** is for delegation at the end of non-trivial work: pass it the ask + diff; it re-runs verification itself and returns PASS/FAIL with evidence.
- **/lesson** writes 0–3 atomic lessons per session. Zero is a valid answer.

## Consolidation

Lessons rot without pruning. `/consolidate` runs the full pass — lessons merge-and-retire, duplicate-thought pruning, tool-failure-log mining, and a report-only skills audit. Run it by hand monthly. The nightly `ops/ob-dream.sh` cron job runs a narrower, capped prompt (`ops/ob-dream.md`: thought dedup and lesson merge/retire only).
