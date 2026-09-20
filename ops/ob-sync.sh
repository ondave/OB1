#!/usr/bin/env bash
# Periodic local->cloud sync. Sources secrets then runs the engine.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
set -a; . "$HERE/.env.sync"; set +a
exec /home/dave/AIHUB/.venv/bin/python "$HERE/ob-sync.py" "${1:-push}"
