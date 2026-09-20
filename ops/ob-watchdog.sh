#!/usr/bin/env bash
# OB1 local-stack watchdog.
#  1. Ensures every OB1 container has restart=unless-stopped (survives reboots,
#     Docker daemon restarts, and OOM crashes; supabase recreates with
#     restart=no, so we re-apply each run).
#  2. Health-checks the two natively-hosted MCP servers (systemd user units, no
#     longer the Supabase edge runtime — that was retired for leaking ~1 GB RSS
#     on an idle stack). A live server answers 200 (with key) or 401 (its own
#     auth, no key) — both prove it is up. Anything else (000 timeout / 502 /
#     503 boot-error) means it is wedged, so we restart the unit. systemd's
#     Restart=always already covers a hard crash; this catches the case it
#     cannot see — a process that is "up" but no longer serving.
set -uo pipefail
PROJECT=OB1
LOG="/home/dave/AIHUB/OB1/ops/watchdog.log"
ts() { date '+%Y-%m-%dT%H:%M:%S'; }
log() { echo "$(ts) $*" >> "$LOG"; }

for c in $(docker ps -a --format '{{.Names}}' | grep "_${PROJECT}$"); do
  pol="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$c" 2>/dev/null || true)"
  if [ "$pol" != "unless-stopped" ]; then
    docker update --restart unless-stopped "$c" >/dev/null 2>&1 \
      && log "set restart=unless-stopped on $c"
  fi
done

check_mcp() {
  local unit="$1" port="$2" code
  # %{http_code} prints 000 on connection failure; no `|| echo` (that would
  # double-append). Default to 000 only if the substitution is empty.
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 \
    -X POST "http://127.0.0.1:${port}/" -H 'content-type: application/json' \
    -H 'accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' 2>/dev/null)"
  code="${code:-000}"

  if [ "$code" = "200" ] || [ "$code" = "401" ]; then
    return 0
  fi

  log "$unit unhealthy (http=$code) — restarting"
  if systemctl --user restart "$unit" >/dev/null 2>&1; then
    log "restarted $unit"
  else
    log "ERROR: restart of $unit failed"
  fi
}

check_mcp ob1-open-brain-mcp.service 54431
check_mcp ob1-project-tracker-mcp.service 54432
