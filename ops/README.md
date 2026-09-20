# OB1 local-first ops

Run OpenBrain **and** Project-Tracker against the **local** Supabase instance
(zero cloud edge-function invocations), and mirror the data to the cloud
instance periodically as a backup / multi-client read replica.

## Why

Cloud **edge-function invocations** were the quota drain: every MCP call
(`/functions/v1/open-brain-mcp`, `/functions/v1/project-tracker-mcp`) hit the
cloud. Both MCP servers now run **locally**, so this machine spends no cloud
invocations. The cloud copy is kept current by a sync that uses **PostgREST**
(`/rest/v1`), which is NOT an edge-function invocation.

## Runtime footprint

The local stack is trimmed to the three services Open Brain actually uses. The
Supabase **edge runtime was retired** (2026-07-29): it leaked ~1 GB RSS on an
idle stack (measured 872 MiB -> 1.05 GiB over ~40 min), needed a 3-minute cron
watchdog to stay alive, and had a history of OOM kills. Both MCP functions are
now hosted natively by systemd user units running the **same unmodified
sources** under bare Deno — they end in `Deno.serve(app.fetch)`, which is
standard Deno, so no code change was required and `supabase functions deploy`
still works against the cloud project from the same files.

| | before | after |
|---|---|---|
| containers | 8 (~1355 MiB) | 3 (~209 MiB) |
| MCP hosting | edge runtime container (~1 GB, leaking) | 2 Deno procs (~90 MiB ea, `MemoryMax=512M`) |
| **total** | **~1355 MiB** | **~387 MiB** |

Disabled in `supabase/config.toml`: `edge_runtime`, `auth`, `realtime`,
`studio`, `inbucket` (plus `storage`/`analytics`, already off). Nothing in
either MCP function calls `supabase.auth.*`, `.storage`, or `.channel` — they
use 7 tables and 3 RPCs over PostgREST with the service-role key, and PostgREST
validates JWTs from the shared secret without GoTrue running.

Studio is off by default. To browse the DB, either use psql directly:

```bash
docker exec -it supabase_db_OB1 psql -U postgres
```

or flip `[studio] enabled = true` in `supabase/config.toml` and re-run
`supabase start` (a `-x` exclusion cannot re-enable a service the config has
disabled), then set it back afterwards.

## Topology

```
Claude (this machine)
  ├─ open-brain       -> http://127.0.0.1:54431/   systemd: ob1-open-brain-mcp
  └─ project-tracker  -> http://127.0.0.1:54432/   systemd: ob1-project-tracker-mcp
                          both = bare Deno running the unmodified edge-function
                          sources; both talk to ONE local Postgres via PostgREST
                          (Kong :54421) using the service-role key
ob-sync.py (cron, every 15m)
        local /rest/v1  ──push──>  cloud /rest/v1   (PostgREST, no edge-fn invocations;
                                                     delete cloud rows missing locally,
                                                     then upsert all rows - reads ids only)
ob-backup.sh (cron, nightly 00:30)
        local pg_dump -Fc -n public  ──>  ~/.local/share/openbrain/backups (7 days)
ob-dream.sh (cron, nightly 01:00)
        claude -p --model opus  ──>  open-brain :54431 + project-tracker :54432   (ob-dream.md)
```

Project-tracker is its own scoped MCP function (idiomatic OpenBrain "recipe",
matches the cloud topology) sharing the same DB — see `primitives/shared-mcp`.

## Files

| File | Purpose |
|------|---------|
| `ob-sync.py`      | Sync engine. Mirrors all 7 tables local -> cloud over PostgREST (delete-reconcile + upsert). |
| `ob-sync.sh`      | Cron wrapper: sources `.env.sync`, runs `ob-sync.py push`. |
| `ob-backup.sh`    | Nightly `pg_dump` of the local `public` schema; keeps 7 days. |
| `ob-dream.sh`     | Nightly headless Claude Code run (Opus): merges duplicate thoughts, retires superseded lessons, tidies project-tracker steps and items, all under hard caps. `--full`, `--dry-run`. |
| `ob-dream.md`     | The prompt `ob-dream.sh` runs. |
| `run-mcp.sh`      | Launches one MCP function natively under Deno. `run-mcp.sh <fn> <port>`. |
| `ob-watchdog.sh`  | Health-checks both MCP units; enforces `restart=unless-stopped`. |
| `.env.sync`       | Local + cloud REST credentials. **gitignored.** |
| `.env.mcp`        | Runtime env for the native MCP servers. **gitignored, mode 600.** |
| `ob1.crontab`     | The cron schedule to install (see below). |

Port is set via `DENO_SERVE_ADDRESS` (Deno >= 2.x) rather than a code change, so
the function sources stay byte-identical to what deploys to the cloud project.
`run-mcp.sh` also passes `--no-lock`: this host runs Deno 2.x, which writes v5
lockfiles, but the edge runtime / deploy path is pinned to `deno_version = 1`
and cannot read v5 — a stray `deno.lock` in a function dir would break
`supabase functions deploy`. Keep those directories to sources only.

## Sync

Capture happens **locally only**, so the cloud is a one-way mirror.

- `./ob-sync.sh push` — local -> cloud (scheduled every 15 min). Deletes cloud
  rows whose id no longer exists locally (children before parents), then
  upserts every row of all 7 tables (projects, work_items, project_decisions,
  project_next_steps, project_references, thoughts, lessons — embeddings
  included). Deletes run first so a row deleted and re-captured locally (new
  id, same `content_fingerprint`) cannot hit the cloud's unique index and fail
  every run. The delete step is skipped for any table that is empty locally,
  so a wiped local instance cannot wipe the cloud. Reads page until an empty
  page, so a server `max_rows` cap cannot truncate the local id set.
- `./ob-sync.sh pull-all` — cloud -> local, ALL tables, never deletes. One-off
  disaster recovery onto an empty/lost local instance only; never schedule it.
  Prefer the local dumps (see **Backups**) first.
- **Egress budget.** Supabase bills data *leaving* the cloud; uploads are not
  billed. Push reads only the `id` columns from the cloud (~33 KB/run,
  ~95 MB/month against the Free plan's 5 GB). Never schedule a job that reads
  full rows from the cloud.
- **Retired 2026-09-11:** the scheduled `pull` (cloud -> local, thoughts +
  lessons) downloaded every row with its 1536-dim embedding each run
  (~7.8 MB/run, ~22 GB/month) and was what kept tripping
  `HTTP 402 exceed_egress_quota`. It also re-upserted every local row, so the
  `updated_at` trigger bumped all rows every 15 min. The separate systemd
  `openbrain-sync.timer` (`~/.local/share/openbrain/sync-to-cloud.sh`: psql via
  the pooler, thoughts only) duplicated the push and raced it; it is disabled,
  unit files left in place. Backups of the pre-change files:
  `.backup-20260911-push-only/`.
- The cloud mirror only updates while the project is not quota-restricted;
  local is unaffected either way.

## Backups

`ob-backup.sh` (cron, nightly 00:30, before the 01:00 dream) writes `pg_dump -Fc -n public` of the local
DB (7 tables + RPCs) to `~/.local/share/openbrain/backups/ob1-*.dump` (dir mode
700, outside the repo) and prunes dumps older than 7 days. These are the
point-in-time copies: the cloud mirror propagates deletes, so it is no
protection against a bad local delete.

Inspect or restore into a scratch database, then copy back what you need:

```bash
D=~/.local/share/openbrain/backups/ob1-YYYYMMDD-HHMMSS.dump
docker exec -i supabase_db_OB1 pg_restore --list < "$D"
docker exec supabase_db_OB1 createdb -U postgres ob1_restore
docker exec supabase_db_OB1 psql -U postgres -d ob1_restore \
  -c 'create schema extensions' -c 'create extension vector schema extensions'
docker exec -i supabase_db_OB1 pg_restore -U postgres -d ob1_restore --no-owner --no-acl < "$D"
```

In a scratch DB `pg_restore` exits 1 with 8 ignored errors — `schema "public"
already exists` and 7 RLS policies that reference Supabase's `auth` schema.
All table data (embeddings included) and the 9 functions still restore
(verified 2026-09-11). Drop it afterwards:
`docker exec supabase_db_OB1 dropdb -U postgres ob1_restore`.

## Dream (nightly memory consolidation)

`ob-dream.sh` (cron, 01:00) runs `claude -p --model opus` on the Claude
subscription (no API key) with the prompt in `ob-dream.md` against the local
Open Brain and project-tracker MCPs. Deliberately conservative: merge
exact/near-duplicate thoughts (keep the most complete or newest), delete
superseded breadcrumbs, retire lessons that are contradicted or merged; in the
tracker tables, complete next steps the project's own records show as done,
drop exact-duplicate steps, and cancel duplicate work items with a note naming
the survivor. Hard caps per run: 10 thought deletions, 5 merges, 5 lesson
retirements, 10 tracker changes; nothing under 48 h old; no
`reference`/`person_note` thoughts; lessons retired, never deleted. The
tracker MCP has no delete tool, so nothing is ever removed there: stale steps
and items, idle projects and duplicate decisions are reported, not changed. It
captures no breadcrumb of its own (that would crowd the session-start
injection): the report goes to `dream.log`, and the full transcript is kept
under `~/.claude/projects/` (the job runs from `$HOME`), which is the audit
trail of what it deleted.

- Nightly mode looks at the last 14 days of thoughts (plus all lessons).
  `./ob-dream.sh --full` reviews every thought; run it by hand now and then —
  the caps still apply, so a big backlog takes several runs.
- Preview without changing anything: `./ob-dream.sh --dry-run` (combinable
  with `--full`).
- Undo: `delete_thought` is permanent — restore from the 00:30 dump (see
  **Backups**). `retire_lessons` only sets `status='retired'`; reactivate with
  `update lessons set status='active' where id=...`.
- The fuller monthly pass (`/consolidate`: failure-log mining, skills audit)
  is by hand.

## Watchdog / auto-restart

Two independent layers:

1. **systemd** (`Restart=always`, `RestartSec=3`) revives either MCP server on a
   hard crash — verified by `kill -9`. `MemoryMax=512M` caps any future leak
   instead of letting it eat the host.
2. **`ob-watchdog.sh`** (cron, every 3 min) catches what systemd cannot see — a
   process that is "up" but no longer serving (hang / boot-error). It POSTs
   `tools/list` to both ports; 200 or 401 both prove liveness, anything else
   triggers `systemctl --user restart`. It also re-applies
   `restart=unless-stopped` to the OB1 containers, since `supabase start` resets
   the policy to `no`.

Historic outage cause: the edge runtime was OOM-killed (exit 137) under host
memory pressure and stayed down. That runtime is now retired — see
**Runtime footprint**.

## Install the schedule

`crontab` could not be set from the agent session. Install it yourself:

```bash
crontab ob1.crontab        # from /home/dave/AIHUB/OB1/ops
crontab -l                 # verify
```

(Merge with any existing crontab if you already have one:
`crontab -l 2>/dev/null | cat - ob1.crontab | crontab -`)

The existing `ob-watchdog.sh` cron line is unchanged — the script itself was
retargeted at the systemd units, so no crontab edit was needed.

## systemd units

```bash
systemctl --user status  ob1-open-brain-mcp ob1-project-tracker-mcp
systemctl --user restart ob1-open-brain-mcp
journalctl --user -u ob1-open-brain-mcp -f      # or ops/open-brain-mcp.log
```

Units live in `~/.config/systemd/user/`. `loginctl enable-linger dave` is
already set, so they start at boot without a login session.

## MCP client config

`~/.claude.json` points both servers at the native ports:

```
open-brain      -> http://127.0.0.1:54431/
project-tracker -> http://127.0.0.1:54432/
```

**Restart Claude Code** for the MCP client to pick up a URL change.
