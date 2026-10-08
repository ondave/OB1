#!/usr/bin/env bash
# Nightly memory "dream": headless Claude Code (Opus, on the Claude subscription)
# runs the prompt in ob-dream.md against the local Open Brain and
# project-tracker MCPs — merge duplicate thoughts, retire superseded lessons,
# complete/dedupe next steps, cancel duplicate work items, and close tracker
# items whose Linear issue or PR says they are finished — under the hard caps
# the prompt sets. Scheduled by the ob1-dream.timer systemd user unit (01:00,
# Persistent=true, so a night the machine was off runs at next boot); also
# runnable by hand.
#
#   ob-dream.sh            nightly pass: last 14 days of thoughts + all lessons + tracker
#   ob-dream.sh --full     whole-brain pass over every thought; run by hand now and then
#   ob-dream.sh --dry-run  report what would change and change nothing (combinable)
#   ob-dream.sh --force    run even if a nightly pass completed in the last 12 hours
#                          (that guard also blocks a manual --full within 12 h)
#
# Safety: deletions are permanent and the 00:30 dump is the only undo, so a
# non-dry run with no backup from the last 26 hours runs as a dry run instead.
#
# Around the model run:
#   - ob-dream-precheck.sh scans for credential-shaped strings and dead repo
#     paths (ids only, never values);
#   - ob-dream-review.py compares tonight's REVIEW block with previous nights
#     and writes the digest the fable-mode SessionStart hook shows.
# State lives in $OB_DREAM_STATE (default ~/.local/state/openbrain/dream).

set -euo pipefail

# cron/systemd PATH is minimal; claude (and uv/ruff) live in ~/.local/bin.
export PATH="$HOME/.local/bin:$PATH"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_FILE="$HERE/ob-dream.md"
STATE_DIR="${OB_DREAM_STATE:-$HOME/.local/state/openbrain/dream}"
mkdir -p "$STATE_DIR"

MODE="NIGHTLY: the step-2 candidate window is list_thoughts with days=14, limit=50."
MODE_NAME=NIGHTLY
DRY_TEXT="DRY RUN: change nothing. Call no write tool: not delete_thought, retire_lessons, store_lesson or capture_thought, and not complete_next_step, set_next_steps, update_work_item, add_work_item, upsert_project, set_reference or log_decision. Produce the same report, prefixing every action line with WOULD."
DRY=""
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --full)    MODE="FULL: the step-2 candidate window is every thought (list_thoughts with limit=400, no days filter)."; MODE_NAME=FULL ;;
    --dry-run) DRY="$DRY_TEXT" ;;
    --force)   FORCE=1 ;;
    *) echo "usage: $0 [--full] [--dry-run] [--force]" >&2; exit 2 ;;
  esac
done

if [ ! -f "$PROMPT_FILE" ]; then
  echo "dream prompt not found at $PROMPT_FILE" >&2
  exit 1
fi

# One run at a time (a manual run must not overlap the timer).
exec 9>"$STATE_DIR/lock"
if ! flock -n 9; then
  echo "=== dream skipped $(date '+%Y-%m-%d %H:%M:%S'): another run holds $STATE_DIR/lock ==="
  exit 0
fi

# A Persistent=true catch-up at boot must not repeat a pass that already ran.
STAMP="$STATE_DIR/last-nightly"
if [ -z "$DRY" ] && [ "$FORCE" = 0 ] && [ -f "$STAMP" ] \
   && [ "$(( $(date +%s) - $(stat -c %Y "$STAMP") ))" -lt 43200 ]; then
  echo "=== dream skipped $(date '+%Y-%m-%d %H:%M:%S'): a pass completed $(date -r "$STAMP" '+%Y-%m-%d %H:%M'); use --force to rerun ==="
  exit 0
fi

# After a boot catch-up the MCP servers may still be starting: wait up to 3 min.
# 200 (with key) or 401 (own auth) both prove a server is serving.
mcp_up() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 \
    -X POST "http://127.0.0.1:$1/" -H 'content-type: application/json' \
    -H 'accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' 2>/dev/null)"
  [ "$code" = "200" ] || [ "$code" = "401" ]
}
for _ in $(seq 1 18); do
  mcp_up 54431 && mcp_up 54432 && break
  sleep 10
done
if ! { mcp_up 54431 && mcp_up 54432; }; then
  echo "=== dream aborted $(date '+%Y-%m-%d %H:%M:%S'): Open Brain / project-tracker MCP not answering on 54431/54432 ===" >&2
  exit 1
fi

RUN_DIR="$(mktemp -d "$STATE_DIR/run.XXXXXX")"
trap 'rm -rf "$RUN_DIR"' EXIT
PRECHECK="$RUN_DIR/precheck.tsv"
REPORT="$RUN_DIR/report.txt"

# No recent backup means no undo for a permanent delete: downgrade to a dry run.
BACKUP_DIR=/home/dave/.local/share/openbrain/backups
if [ -z "$DRY" ] && [ -z "$(find "$BACKUP_DIR" -maxdepth 1 -name 'ob1-*.dump' -mmin -1560 2>/dev/null | head -1)" ]; then
  DRY="$DRY_TEXT"
  printf 'NOBACKUP\n' > "$PRECHECK.flags"
  echo "no backup newer than 26 h in $BACKUP_DIR: running as a DRY RUN"
fi

echo "=== dream run $(date '+%Y-%m-%d %H:%M:%S') ${MODE_NAME}${DRY:+ (dry run)} ==="

if "$HERE/ob-dream-precheck.sh" > "$PRECHECK"; then
  echo "precheck: $(grep -c '^SECRET' "$PRECHECK" || true) secret-shaped row(s), $(grep -c '^DEADPATH' "$PRECHECK" || true) dead repo path(s)"
  # ids, tables and slugs only (the precheck never prints values)
  cat "$PRECHECK"
else
  echo "precheck FAILED (DB unreachable?); continuing without it"
  printf 'PRECHECKFAILED\n' > "$PRECHECK"
fi
[ -f "$PRECHECK.flags" ] && cat "$PRECHECK.flags" >> "$PRECHECK"

DEADPATHS="$(grep '^DEADPATH' "$PRECHECK" | cut -f2- | sed 's/^/- /' || true)"
PROMPT="$(cat "$PROMPT_FILE")

MODE $MODE
$DRY

PRECHECK
Projects whose repo path no longer exists on disk (DEADPATH):
${DEADPATHS:-- none}"

# Read-only external lookups for step 4a; the MCP servers' own tools are
# allowed by the session's settings as before.
ALLOWED_TOOLS=(
  "mcp__linear-server__get_issue"
  "mcp__linear-eidosxr__get_issue"
  "mcp__gitlab__get_merge_request"
  "Bash(gh pr view *)"
  "Bash(gh issue view *)"
)

# </dev/null: no stdin under cron/systemd and claude otherwise waits 3 s for it.
rc=0
claude -p "$PROMPT" --model opus --permission-mode acceptEdits \
  --allowedTools "${ALLOWED_TOOLS[@]}" </dev/null 9>&- | tee "$REPORT" || rc=$?

# A backup-forced dry run still records state and the digest, so the missing
# backup is seen at session start; only a requested --dry-run writes nothing.
review_args=(--report "$REPORT" --precheck "$PRECHECK" --state-dir "$STATE_DIR" --mode "$MODE_NAME")
case " $* " in *" --dry-run "*) review_args+=(--dry-run) ;; esac
python3 "$HERE/ob-dream-review.py" "${review_args[@]}" || true

if [ "$rc" = 0 ] && [ -z "$DRY" ] && [ "$MODE_NAME" = NIGHTLY ]; then
  # (a backup-forced dry run does not stamp, so the next run retries for real)
  touch "$STAMP"
fi
echo "=== done $(date '+%Y-%m-%d %H:%M:%S') (claude exit $rc) ==="
exit "$rc"
