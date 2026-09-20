#!/usr/bin/env python3
"""OpenBrain / Project-Tracker local -> cloud mirror.

Mirrors the seven Supabase tables from the local instance (source of truth;
all capture happens locally) to the cloud instance (remote backup / read
mirror) over PostgREST.

  push      local -> cloud (default; scheduled periodically): delete cloud
            rows whose id no longer exists locally, then upsert every row
  pull-all  cloud -> local, all tables (one-off disaster recovery)

Strategy: full-table upsert keyed on the primary key (id) with
`resolution=merge-duplicates`. Tables are tiny (<200 rows each) so a full
upsert every run is cheap and is the *correct* choice for the two tables that
carry no updated_at column (project_decisions, project_next_steps) - it always
catches supersessions and step completions. Uploads are ingress, which
Supabase does not bill.

Egress: push reads only `id` from the cloud (~33 KB/run, for the delete
step). Never schedule anything that reads full rows from the cloud - the
retired scheduled `pull` (every thought + lesson with embeddings, ~7.8 MB/run)
exhausted the Free-plan egress quota (see ops/README.md).

Delete-reconcile is skipped for any table that is empty locally, so a wiped
local instance cannot wipe the cloud copy. pull-all never deletes.

Credentials come from the environment (see ops/.env.sync):
  OB_LOCAL_URL  OB_LOCAL_KEY   OB_CLOUD_URL  OB_CLOUD_KEY
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

# Parents before children so FK (project_id) constraints are satisfied when the
# destination starts empty.
TABLES = [
    "projects",
    "work_items",
    "project_decisions",
    "project_next_steps",
    "project_references",
    "thoughts",
    "lessons",
]

PAGE = 1000
CHUNK = 200
ID_CHUNK = 100  # ids per DELETE ?id=in.(...) - keeps the URL short


def _req(base, key, path, method="GET", body=None, prefer=None):
    url = f"{base}/rest/v1/{path}"
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:500]
        raise SystemExit(f"HTTP {e.code} on {method} {path}: {detail}") from None


def fetch_all(base, key, table, select="*"):
    # Page until an empty page: a short page may only mean the server's
    # max_rows cap is below PAGE, and a truncated local read would make push
    # delete cloud rows that still exist locally.
    rows = []
    offset = 0
    while True:
        page = _req(
            base,
            key,
            f"{table}?select={select}&order=id.asc&limit={PAGE}&offset={offset}",
        )
        if not page:
            return rows
        rows.extend(page)
        offset += len(page)


def upsert(base, key, table, rows):
    for i in range(0, len(rows), CHUNK):
        _req(
            base,
            key,
            table,
            method="POST",
            body=rows[i : i + CHUNK],
            prefer="resolution=merge-duplicates,return=minimal",
        )
    return len(rows)


def delete_missing(base, key, table, keep_ids):
    """Delete rows in `table` whose id is not in keep_ids. Reads ids only."""
    stale = sorted(
        r["id"]
        for r in fetch_all(base, key, table, select="id")
        if r["id"] not in keep_ids
    )
    for i in range(0, len(stale), ID_CHUNK):
        ids = ",".join(stale[i : i + ID_CHUNK])
        _req(
            base,
            key,
            f"{table}?id=in.({ids})",
            method="DELETE",
            prefer="return=minimal",
        )
    return len(stale)


def main():
    direction = sys.argv[1] if len(sys.argv) > 1 else "push"
    try:
        local = (os.environ["OB_LOCAL_URL"], os.environ["OB_LOCAL_KEY"])
        cloud = (os.environ["OB_CLOUD_URL"], os.environ["OB_CLOUD_KEY"])
    except KeyError as e:
        raise SystemExit(f"missing env var {e}; source ops/.env.sync") from None

    if direction == "push":
        src, dst, arrow = local, cloud, "local -> cloud"
    elif direction == "pull-all":
        src, dst, arrow = cloud, local, "cloud -> local (ALL)"
    else:
        raise SystemExit("usage: ob-sync.py [push|pull-all]")

    src_rows = {table: fetch_all(src[0], src[1], table) for table in TABLES}

    deleted = 0
    if direction == "push":
        # Delete before upsert: a row deleted locally and re-captured (new id,
        # same content_fingerprint) would otherwise hit the cloud's unique index
        # and fail every run. Children before parents, so this also holds if an
        # FK is ever RESTRICT.
        for table in reversed(TABLES):
            keep_ids = {r["id"] for r in src_rows[table]}
            if not keep_ids:
                print(f"  {table}: empty locally, delete-reconcile skipped")
                continue
            d = delete_missing(dst[0], dst[1], table, keep_ids)
            deleted += d
            if d:
                print(f"  {table}: {d} deleted")

    total = 0
    for table in TABLES:
        n = upsert(dst[0], dst[1], table, src_rows[table])
        total += n
        print(f"  {table}: {n} rows")
    print(
        f"sync {arrow}: {total} rows across {len(TABLES)} tables, {deleted} deleted OK"
    )


if __name__ == "__main__":
    main()
