#!/usr/bin/env bash
# Nightly memory "dream": headless Claude Code (Opus, on the Claude subscription)
# runs the prompt in ob-dream.md against the local Open Brain and
# project-tracker MCPs — merge duplicate thoughts, retire superseded lessons,
# complete/dedupe next steps, cancel duplicate work items — under the hard
# caps the prompt sets. Scheduled from ob1.crontab (01:00, after the 00:30 backup);
# also runnable by hand.
#
#   ob-dream.sh            nightly pass: last 14 days of thoughts + all lessons + tracker
#   ob-dream.sh --full     whole-brain pass over every thought; run by hand now and then
#   ob-dream.sh --dry-run  report what would change and change nothing (combinable)

set -euo pipefail

# cron's PATH is only /usr/bin:/bin; claude (and uv/ruff) live in ~/.local/bin.
export PATH="$HOME/.local/bin:$PATH"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_FILE="$HERE/ob-dream.md"

MODE="NIGHTLY: the step-2 candidate window is list_thoughts with days=14, limit=50."
DRY=""
for arg in "$@"; do
  case "$arg" in
    --full)    MODE="FULL: the step-2 candidate window is every thought (list_thoughts with limit=400, no days filter)." ;;
    --dry-run) DRY="DRY RUN: change nothing. Do not call delete_thought, retire_lessons, store_lesson or capture_thought. Produce the same report, prefixing every action line with WOULD." ;;
    *) echo "usage: $0 [--full] [--dry-run]" >&2; exit 2 ;;
  esac
done

if [ ! -f "$PROMPT_FILE" ]; then
  echo "dream prompt not found at $PROMPT_FILE" >&2
  exit 1
fi

PROMPT="$(cat "$PROMPT_FILE")

MODE $MODE
$DRY"

echo "=== dream run $(date '+%Y-%m-%d %H:%M:%S') ${MODE%%:*}${DRY:+ (dry run)} ==="
# </dev/null: cron gives no stdin and claude otherwise waits 3 s for it.
claude -p "$PROMPT" --model opus --permission-mode acceptEdits </dev/null
echo "=== done $(date '+%Y-%m-%d %H:%M:%S') ==="
