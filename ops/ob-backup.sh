#!/usr/bin/env bash
# Nightly snapshot of the local OpenBrain DB: `public` schema (7 tables + RPCs).
# Point-in-time copies the cloud mirror cannot give (push propagates deletes).
set -euo pipefail
umask 077
DEST=/home/dave/.local/share/openbrain/backups
mkdir -p "$DEST"
OUT="$DEST/ob1-$(date +%Y%m%d-%H%M%S).dump"
trap 'rm -f "$OUT.tmp"' EXIT
docker exec supabase_db_OB1 pg_dump -U postgres -Fc -n public > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
# Keep 7 days (-mtime +6 = at least 7 full days old).
find "$DEST" -maxdepth 1 -name 'ob1-*.dump' -mtime +6 -delete
echo "$(date -Is) backup ok: $OUT ($(stat -c %s "$OUT") bytes)"
