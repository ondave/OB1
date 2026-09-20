#!/usr/bin/env bash
# Launch an OB1 MCP edge-function natively under Deno.
#
# The function sources are unmodified Supabase edge functions — they end in a
# bare `Deno.serve(app.fetch)`, which is standard Deno, so they run outside the
# edge runtime verbatim. `supabase functions deploy` still works from the same
# source; only the LOCAL host process differs.
#
# Port is set via DENO_SERVE_ADDRESS (Deno >= 2.x) rather than a code change,
# so the sources stay byte-identical to what deploys to the cloud project.
#
# Usage: run-mcp.sh <function-name> <port>
set -euo pipefail

NAME="${1:?usage: run-mcp.sh <function-name> <port>}"
PORT="${2:?usage: run-mcp.sh <function-name> <port>}"

OB1_ROOT="/home/dave/AIHUB/OB1"
FN_DIR="${OB1_ROOT}/supabase/functions/${NAME}"
DENO="/home/dave/.deno/bin/deno"
ENV_FILE="${OB1_ROOT}/ops/.env.mcp"

[ -d "$FN_DIR" ] || { echo "no such function dir: $FN_DIR" >&2; exit 1; }
[ -r "$ENV_FILE" ] || { echo "missing env file: $ENV_FILE" >&2; exit 1; }

# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a
export DENO_SERVE_ADDRESS="tcp:127.0.0.1:${PORT}"

# --no-lock is deliberate: this host runs Deno 2.x, which writes v5 lockfiles,
# but the edge runtime / cloud deploy path is pinned to deno_version = 1 and
# cannot read v5. Letting Deno drop a lockfile into the function dir would
# break `supabase functions deploy`. Keep these directories to sources only.
cd "$FN_DIR"
exec "$DENO" run \
  --allow-net \
  --allow-env \
  --allow-read \
  --no-lock \
  --config deno.json \
  index.ts
