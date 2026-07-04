# Lessons Ledger

> A dedicated store for operational lessons learned — separate from general thoughts, scoped by repo, searchable by meaning, and consolidatable without touching the rest of your brain.

## What It Does

Adds a `lessons` table (with pgvector embedding, repo tag, category, and active/retired status) plus two RPCs: `match_lessons` for semantic search and `upsert_lesson` for fingerprint-deduplicated writes. Lessons are atomic "context → mistake → rule" entries that an AI client stores when something surprising happens and retrieves mechanically at the start of a session.

Why not just use `thoughts`? Two reasons, both learned the hard way:

1. **Routing.** When lessons and general notes share one store, clients capture session diaries as "lessons" and retrieve grocery notes when debugging. A separate table with explicitly-scoped MCP tool descriptions ("for operational lessons learned, NOT general notes") keeps the two streams clean.
2. **Consolidation.** Lessons rot into contradiction piles without periodic pruning. A dedicated table makes "list everything active for repo X, merge duplicates, retire stale rules" a cheap monthly query instead of an archaeology dig.

## Prerequisites

- Working Open Brain setup ([guide](../../docs/01-getting-started.md)) — you need the `thoughts` table's `update_updated_at()` trigger function and the pgvector extension it enables.

## Steps

### 1. Apply the schema

Open the Supabase SQL Editor (or `psql` against your instance) and run [`schema.sql`](./schema.sql). It is additive and idempotent for tables/indexes/functions; the policy and trigger statements error harmlessly if re-run.

✅ **Done when:** Table Editor shows a `lessons` table and Database → Functions shows `match_lessons` and `upsert_lesson`.

### 2. Add MCP tools to your Open Brain server

In your `open-brain-mcp` edge function, register lesson tools alongside the thought tools. The important part is the tool descriptions — they are routing hints, and without the explicit "NOT for..." clauses clients will store lessons as thoughts and vice versa:

- `store_lesson(content, repo?, category?, topics?)` — "Save an operational lesson learned — a concrete mistake and the rule that prevents repeating it. NOT for general notes, ideas, or observations (use capture_thought)." Embed the content, then call `upsert_lesson` and update the row's embedding.
- `search_lessons(query, repo?, limit?, threshold?)` — "Search past lessons learned before starting or debugging work. NOT for general notes (use search_thoughts)." Embed the query, then call `match_lessons`.
- `list_lessons(...)` / `retire_lessons(ids)` — for the periodic consolidation pass: list what's active, merge duplicates into one better lesson (`store_lesson`), retire the originals.

### 3. Wire retrieval into your client (recommended)

Pull-based retrieval fails quietly — the model has to *decide* to search, and deep into a session it won't. If your client supports lifecycle hooks (e.g. Claude Code plugins), inject the top few repo-relevant lessons at session start so retrieval happens mechanically. See `integrations/claude-code-fable-mode/` for a complete example.

## Consolidation

Monthly (or when `list_lessons` output starts contradicting itself):

1. `list_lessons` for each active repo plus globals.
2. Merge near-duplicates into one sharper rule via `store_lesson`.
3. `retire_lessons` on the originals — soft retirement, nothing is deleted.
