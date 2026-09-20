# Personal Assistant

## Why This Matters

If you run a set of personal-assistant subagents (email, calendar, tasks,
research, writing, developer), each one needs the same context before it can
act for you: who you are, who your contacts are, and how you like each kind of
work done. Keeping that in `profile.json`, `contacts.json`, and a pile of
per-agent `memory.json` files means every agent re-reads files, the data
fragments, and nothing is shared across the other AI clients plugged into your
brain. This recipe replaces that scaffolding with one structured store every
client can query in a single tool call.

## What It Does

Adds an MCP server that stores three things in your Open Brain Supabase:

- **Profile** — your identity card: name, role, company, work hours, timezone,
  work days, communication style, current projects.
- **Contacts** — a lightweight CRM of people you draft to / schedule with.
- **Preferences** — per-domain assistant settings (email tone and signature,
  calendar buffers and focus time, task workspaces, research/writing defaults,
  developer conventions) as typed key/value rows.

Seven tools let you and your AI read and write that state without touching a
flat file:

| Tool | Purpose |
| ---- | ------- |
| `get_profile` | Read the identity profile |
| `set_profile` | Create/update the profile (partial updates preserved) |
| `list_contacts` | List contacts, optional tag/company filter |
| `get_contact` | Read one contact by slug |
| `upsert_contact` | Create/update a contact by slug |
| `get_preferences` | Read preferences by domain (and optional key) |
| `set_preference` | Create/update one preference (JSON value) |

## Prerequisites

- Working Open Brain setup ([guide](../../docs/01-getting-started.md))
- Supabase CLI installed and linked to your Open Brain project
- An `MCP_ACCESS_KEY` and `DEFAULT_USER_ID` already configured for the core
  Open Brain function (this recipe reuses them)

## Credential Tracker

```text
PERSONAL ASSISTANT -- CREDENTIAL TRACKER
----------------------------------------

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

----------------------------------------
```

## Setup

1. **Apply the schema.** Run `schema.sql` against your Open Brain Supabase
   (via the SQL editor or `supabase db execute`). It creates `pa_profile`,
   `pa_contacts`, and `pa_preferences` with RLS and `updated_at` triggers.

2. **Deploy the Edge Function.** Copy `index.ts` and `deno.json` into a new
   function folder (e.g. `supabase/functions/personal-assistant/`) and deploy:

   ```bash
   supabase functions deploy personal-assistant --no-verify-jwt
   ```

3. **Set secrets.** Reuse the core Open Brain values:

   ```bash
   supabase secrets set MCP_ACCESS_KEY=... DEFAULT_USER_ID=...
   ```

   (`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.)

4. **Connect the MCP server.** Add the function URL as a custom connector:

   ```
   https://<project-ref>.supabase.co/functions/v1/personal-assistant
   ```

   Authenticate with the `x-brain-key` header set to your `MCP_ACCESS_KEY`.

5. **Seed your data.** Move your identity into the store:

   - `set_profile` with your name, role, company, work hours, timezone, work
     days, communication style, current projects.
   - `upsert_contact` for each person you correspond with.
   - `set_preference` per domain for the settings your subagents rely on.

## How It Fits the Assistant Subagents

Each personal-assistant subagent keeps sensible defaults baked into its own
definition so it works even if this server is unreachable. When it needs fresh
or richer context it calls this MCP:

- **email** → `get_profile`, `get_preferences(domain='email')`, `get_contact`
- **calendar** → `get_profile`, `get_preferences(domain='calendar')`
- **tasks** → `get_preferences(domain='tasks')` (Asana workspace ids)
- **research / writing** → `get_profile`, `get_contact`
- **developer** → `get_preferences(domain='developer')`

## Notes

- This is the structured home for *stable* identity and preference data.
  Free-form, evolving notes still belong in core Open Brain thoughts; durable
  project state belongs in the [Project Tracker](../project-tracker/) recipe.
- The schema uses namespaced `pa_*` trigger functions so it can coexist with
  other recipes/extensions in the same database.
