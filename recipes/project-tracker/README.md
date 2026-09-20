# Project Tracker

## Why This Matters

If you juggle multiple software projects across Linear/Jira/GitHub/GitLab, the "where am I right now on project X" question is expensive. JSON scratchpads go stale. Memory files fragment. Asking your AI for status means it re-reads a file, searches a vector store, and still guesses. This recipe replaces that with one structured store you can query in one tool call.

## What It Does

Adds an MCP server that tracks projects, work items, decisions, references, and next steps in your Open Brain Supabase. Twelve tools let you (and your AI) read and write project state without touching a flat file.

## Prerequisites

- Working Open Brain setup ([guide](../../docs/01-getting-started.md))
- Supabase CLI installed and linked to your Open Brain project
- An `MCP_ACCESS_KEY` and `DEFAULT_USER_ID` already configured for the core Open Brain function (this recipe reuses them)

## Credential Tracker

```text
PROJECT TRACKER -- CREDENTIAL TRACKER
--------------------------------------

SUPABASE (from your Open Brain setup)
  Project URL:           ____________
  Secret key:            ____________
  Project ref:           ____________

REUSED FROM CORE OPEN BRAIN
  MCP Access Key:        ____________
  Default User ID:       ____________

GENERATED DURING SETUP
  MCP Server URL:        ____________
  MCP Connection URL:    ____________

--------------------------------------
```

---

## Step 1 — Create the Database Tables

In your Supabase SQL Editor (`https://supabase.com/dashboard/project/YOUR_PROJECT_ID/sql/new`), paste the contents of [`schema.sql`](./schema.sql) and Run.

Then run this `GRANT` block in a new query to give `service_role` access (Supabase does not grant this by default):

```sql
grant select, insert, update, delete on table public.projects to service_role;
grant select, insert, update, delete on table public.work_items to service_role;
grant select, insert, update, delete on table public.project_decisions to service_role;
grant select, insert, update, delete on table public.project_references to service_role;
grant select, insert, update, delete on table public.project_next_steps to service_role;
```

> [!IMPORTANT]
> Without the GRANT, every tool call returns `permission denied for table ...`.

✅ **Done when:** Table Editor shows `projects`, `work_items`, `project_decisions`, `project_references`, `project_next_steps`.

---

## Step 2 — Deploy the MCP Server

Follow the [Deploy an Edge Function](../../primitives/deploy-edge-function/) guide using these values:

| Setting | Value |
|---------|-------|
| Function name | `project-tracker-mcp` |
| Download path | `recipes/project-tracker` |

Set these function secrets in the Supabase dashboard (Settings → Edge Functions → Secrets) if they aren't already inherited:

| Secret | Value |
|--------|-------|
| `SUPABASE_URL` | auto-provided |
| `SUPABASE_SERVICE_ROLE_KEY` | auto-provided |
| `MCP_ACCESS_KEY` | same key you use for the core Open Brain server |
| `DEFAULT_USER_ID` | your `auth.users` UUID |

✅ **Done when:** `supabase functions list` shows `project-tracker-mcp` as `ACTIVE`.

---

## Step 3 — Connect to Your AI

Follow the [Remote MCP Connection](../../primitives/remote-mcp/) guide.

| Setting | Value |
|---------|-------|
| Connector name | `Project Tracker` |
| URL | `https://YOUR_PROJECT_ID.supabase.co/functions/v1/project-tracker-mcp?key=YOUR_MCP_ACCESS_KEY` |

✅ **Done when:** Your AI client lists the 12 tools (`list_projects`, `get_project_snapshot`, `upsert_project`, `add_work_item`, `update_work_item`, `list_work_items`, `log_decision`, `list_decisions`, `set_reference`, `list_references`, `set_next_steps`, `complete_next_step`).

---

## Step 4 — Test It

Run these prompts in your AI client (Claude Code, Claude Desktop, etc.):

1. **Create a project:**
   > "Add a project called 'Demo Project' with slug 'demo', priority high, deadline 2026-12-31."

   Expect: `upsert_project` returns the new row.

2. **Add a work item:**
   > "Add a work item to demo: 'Wire up auth' as external_id DEMO-1, status in_progress."

3. **Snapshot it:**
   > "Show me the current state of project demo."

   Expect: `get_project_snapshot` returns the project plus the work item grouped under `in_progress`.

4. **Log a decision:**
   > "Log a decision for demo: always run migrations on staging before prod. Category: workflow."

5. **Set next steps:**
   > "Set next steps for demo: 1) ship auth, 2) wire up billing, 3) add e2e tests."

> [!CAUTION]
> If any prompt returns `permission denied`, you skipped the GRANT in Step 1.

---

## Tool Cheat Sheet

| Tool | Use |
|------|-----|
| `list_projects` | "What am I working on?" |
| `get_project_snapshot(slug)` | One call: full state of one project |
| `upsert_project(slug, ...)` | Create or update top-level fields |
| `add_work_item(project_slug, title, ...)` | New task. `status='deferred'` = backlog you want to remember |
| `update_work_item(external_id+project_slug OR id, ...)` | Status changes, PR links, notes |
| `list_work_items(project_slug?, status?, has_pr?)` | Filtered query |
| `log_decision(title, body, ...)` | Capture a workflow rule or gotcha (replaces feedback_*.md) |
| `list_decisions(project_slug?, category?, tag?)` | Look up rules |
| `set_reference(key, value, ...)` | Save a Linear ID / namespace / path (replaces reference_*.md) |
| `list_references(project_slug?, key_prefix?)` | Look up saved IDs/paths |
| `set_next_steps(project_slug, steps[])` | Replace the active next-steps list |
| `complete_next_step(project_slug, id_or_step)` | Mark one done |

## Cross-Extension Integration

Project Tracker is read-write structured state. Core Open Brain (`thoughts`) is semantic free-text capture. Use them together:

- **Capture first, structure later.** When you don't know yet whether something is a one-off observation or a durable rule, `capture_thought` it. Later, promote the keepers into `log_decision` or `set_reference`.
- **Decisions reference thoughts.** When `log_decision`-ing a rule, paste the originating thought's content into `rationale` so the structured record is self-contained even if the thought is later pruned.
- **Snapshots for sessions, search for archaeology.** Start a session with `get_project_snapshot('eidos')`. Mid-session, when you need "why did we choose Yjs over Automerge", `search_thoughts` against the core store.

## Expected Outcome

After setup you can:

- Ask "what's the state of <project>" and get a one-call structured answer.
- Add/update work items, decisions, references, and next steps via natural language.
- Drop the projects.json scaffold and any feedback_*.md / reference_*.md files once migrated.

## Troubleshooting

**"permission denied for table projects"** — You skipped the GRANT block in Step 1.

**"Project not found: <slug>"** — `upsert_project` first, then `add_work_item`. Slugs are case-sensitive.

**`work_items_external_id_uidx` constraint violation** — You tried to add a work item with the same external_id twice in the same project. Use `update_work_item` instead.

**Empty `get_project_snapshot` work_items_by_status** — Either the project has no items yet, or you used the wrong slug. `list_projects` to confirm.

## Next Steps

- Migrate your existing `projects.json` into the tracker (one `upsert_project` per project, then `add_work_item` per entry).
- Move durable feedback_*.md / reference_*.md memories into `log_decision` / `set_reference` calls.
- Update your AI client's project-bootstrapping instructions to call `get_project_snapshot` at session start instead of reading a flat file.

> **Tool hygiene:** This recipe adds 12 MCP tools to your AI's context window. See the [MCP Tool Audit & Optimization Guide](../../docs/05-tool-audit.md) for strategies on managing total tool count as you stack extensions and recipes.
