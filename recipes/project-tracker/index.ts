/**
 * Project Tracker MCP Server (Remote Edge Function)
 *
 * Tracks software projects, work items, decisions, references, and next steps.
 * Replaces ad-hoc projects.json scaffolding and per-project memory files with a
 * structured, queryable store.
 *
 * Tools:
 *   list_projects, get_project_snapshot, upsert_project
 *   add_work_item, update_work_item, list_work_items
 *   log_decision, list_decisions
 *   set_reference, list_references
 *   set_next_steps, complete_next_step
 */

import { Hono } from "hono";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPTransport } from "@hono/mcp";
import { z } from "zod";
import { createClient } from "@supabase/supabase-js";

const PRIORITY_RANK: Record<string, number> = { high: 0, medium: 1, low: 2 };

type PgError = { message?: string; code?: string };

// First line of the PostgREST message + the SQLSTATE code if present.
// Drops Hint/Details/Query lines that leak schema internals.
function fail(action: string, err: PgError | unknown): never {
  const e = (err ?? {}) as PgError;
  const code = e.code ? ` [${e.code}]` : "";
  const msg = ((e.message ?? "unknown error") + "").split("\n")[0].trim();
  throw new Error(`${action}${code}: ${msg}`);
}

const app = new Hono();

app.post("*", async (c) => {
  // Content-negotiation patch — some MCP connectors omit text/event-stream
  // from Accept, but @hono/mcp requires both for POST.
  if (!c.req.header("accept")?.includes("text/event-stream")) {
    const headers = new Headers(c.req.raw.headers);
    headers.set("Accept", "application/json, text/event-stream");
    const patched = new Request(c.req.raw.url, {
      method: c.req.raw.method,
      headers,
      body: c.req.raw.body,
      // @ts-ignore -- duplex required for streaming body in Deno
      duplex: "half",
    });
    Object.defineProperty(c.req, "raw", { value: patched, writable: true });
  }

  // Auth — accept x-brain-key (Open Brain convention), x-access-key
  // (professional-crm convention), or ?key= query param.
  const key =
    c.req.query("key") ||
    c.req.header("x-brain-key") ||
    c.req.header("x-access-key");
  const expected = Deno.env.get("MCP_ACCESS_KEY");
  if (!key || key !== expected) {
    return c.json({ error: "Unauthorized" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  const userId = Deno.env.get("DEFAULT_USER_ID");
  if (!userId) {
    return c.json({ error: "DEFAULT_USER_ID not configured" }, 500);
  }

  const server = new McpServer({ name: "project-tracker", version: "0.1.0" });

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  const resolveProjectId = async (slug: string): Promise<string> => {
    const { data, error } = await supabase
      .from("projects")
      .select("id")
      .eq("user_id", userId)
      .eq("slug", slug)
      .single();
    if (error) fail(`Project not found: ${slug}`, error);
    return data!.id;
  };

  // Scope a query by project_id, using IS NULL when project_id is null
  // (so the "global" scope is queryable). Avoids the brittle .filter(...) form.
  const scopeByProject = <T>(q: T, project_id: string | null): T => {
    // deno-lint-ignore no-explicit-any
    const qb = q as any;
    return project_id
      ? qb.eq("project_id", project_id)
      : qb.is("project_id", null);
  };

  const ok = (payload: unknown) => ({
    content: [
      { type: "text" as const, text: JSON.stringify(payload, null, 2) },
    ],
  });

  // -------------------------------------------------------------------------
  // PROJECTS
  // -------------------------------------------------------------------------

  server.tool(
    "list_projects",
    "List all tracked projects, optionally filtered by status. Use this when the user asks 'what am I working on' or wants a project overview. Results are sorted high→medium→low priority, then by most recently updated.",
    {
      status: z
        .enum(["active", "in_progress", "paused", "completed", "archived"])
        .optional()
        .describe("Filter by status. Omit to list everything except archived."),
      include_archived: z
        .boolean()
        .optional()
        .describe("Include archived projects in the result (default: false)"),
    },
    async ({ status, include_archived }) => {
      let q = supabase
        .from("projects")
        .select(
          "id, slug, name, status, priority, deadline, description, updated_at",
        )
        .eq("user_id", userId);
      if (status) {
        q = q.eq("status", status);
      } else if (!include_archived) {
        q = q.neq("status", "archived");
      }
      const { data, error } = await q.order("updated_at", { ascending: false });
      if (error) fail("Failed to list projects", error);
      // Alphabetical sort on priority (high>low>medium) is wrong; sort by rank
      // here. updated_at order from the DB is preserved within each priority.
      const sorted = (data ?? []).slice().sort((a, b) => {
        const ra = a.priority ? (PRIORITY_RANK[a.priority] ?? 99) : 99;
        const rb = b.priority ? (PRIORITY_RANK[b.priority] ?? 99) : 99;
        return ra - rb;
      });
      return ok({ count: sorted.length, projects: sorted });
    },
  );

  server.tool(
    "get_project_snapshot",
    "Get the complete current state of a project: top-level fields, all work items grouped by status, next steps, decisions, and references. Use this at the start of any session that touches a known project — replaces reading projects.json.",
    {
      slug: z
        .string()
        .describe("Project slug (e.g. 'eidos', 'oceanum-io-platform')"),
    },
    async ({ slug }) => {
      const { data: project, error: pErr } = await supabase
        .from("projects")
        .select("*")
        .eq("user_id", userId)
        .eq("slug", slug)
        .single();
      if (pErr) fail(`Project not found: ${slug}`, pErr);

      const [items, steps, decisions, refs] = await Promise.all([
        supabase
          .from("work_items")
          .select(
            "id, external_id, title, status, priority, pr_urls, notes, blocked_by, completed_at, updated_at",
          )
          .eq("user_id", userId)
          .eq("project_id", project!.id)
          .order("status")
          .order("updated_at", { ascending: false }),
        supabase
          .from("project_next_steps")
          .select("id, step, position, completed_at")
          .eq("user_id", userId)
          .eq("project_id", project!.id)
          .is("completed_at", null)
          .order("position"),
        supabase
          .from("project_decisions")
          .select(
            "id, title, body, rationale, applies_to, category, tags, superseded_by, created_at",
          )
          .eq("user_id", userId)
          .eq("project_id", project!.id)
          .is("superseded_by", null)
          .order("created_at", { ascending: false }),
        supabase
          .from("project_references")
          .select("key, value, description, updated_at")
          .eq("user_id", userId)
          .eq("project_id", project!.id)
          .order("key"),
      ]);

      // Group work items by status.
      const itemsByStatus: Record<string, unknown[]> = {};
      for (const item of items.data ?? []) {
        (itemsByStatus[item.status] ||= []).push(item);
      }

      return ok({
        project,
        work_items_by_status: itemsByStatus,
        work_item_count: items.data?.length ?? 0,
        next_steps: steps.data ?? [],
        decisions: decisions.data ?? [],
        references: refs.data ?? [],
      });
    },
  );

  server.tool(
    "upsert_project",
    "Create a new project or update an existing one (matched by slug). Pass only the fields you want to set; existing fields are preserved when omitted. To archive a project pass status='archived'. To clear deadline pass deadline=null.",
    {
      slug: z
        .string()
        .describe("Stable short id, e.g. 'eidos', 'oceanum-io-platform'"),
      name: z.string().optional().describe("Human-readable name"),
      status: z
        .enum(["active", "in_progress", "paused", "completed", "archived"])
        .optional(),
      priority: z.enum(["low", "medium", "high"]).optional(),
      deadline: z
        .string()
        .nullable()
        .optional()
        .describe("Deadline as YYYY-MM-DD, or null to clear"),
      description: z.string().optional(),
      notes: z.string().optional(),
      repo_paths: z
        .array(z.string())
        .optional()
        .describe("Local filesystem paths to the repo(s)"),
      stakeholders: z.array(z.string()).optional(),
      tech_stack: z
        .record(z.string(), z.unknown())
        .optional()
        .describe("Free-form JSON object (frontend, backend, etc.)"),
      linear: z
        .record(z.string(), z.unknown())
        .optional()
        .describe("Linear config: workspace, team, team_id, project_id"),
      infrastructure: z.record(z.string(), z.unknown()).optional(),
      metadata: z
        .record(z.string(), z.unknown())
        .optional()
        .describe(
          "Catch-all JSON for project-specific fields (test_counts, ci notes, datasets, schedule, etc.)",
        ),
    },
    async ({ slug, deadline, ...rest }) => {
      // Build the set of fields the caller actually provided. Treat `null` as
      // an explicit clear (currently only deadline accepts null in zod).
      const fields: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(rest)) {
        if (v !== undefined) fields[k] = v;
      }
      if (deadline !== undefined) fields.deadline = deadline;

      // SELECT-then-INSERT/UPDATE so omitted fields are preserved on update.
      // The previous .upsert() reset every unspecified column to its DEFAULT.
      const existing = await supabase
        .from("projects")
        .select("id")
        .eq("user_id", userId)
        .eq("slug", slug)
        .maybeSingle();
      if (existing.error) fail("Failed to look up project", existing.error);

      if (existing.data) {
        if (Object.keys(fields).length === 0) {
          // Nothing to change — return the existing row.
          const { data, error } = await supabase
            .from("projects")
            .select("*")
            .eq("id", existing.data.id)
            .single();
          if (error) fail("Failed to read project", error);
          return ok({ success: true, project: data, action: "noop" });
        }
        const { data, error } = await supabase
          .from("projects")
          .update(fields)
          .eq("id", existing.data.id)
          .select()
          .single();
        if (error) fail("Failed to update project", error);
        return ok({ success: true, project: data, action: "updated" });
      }

      // Insert path: require name for new projects so the row is usable.
      if (!fields.name) {
        throw new Error("name is required when creating a new project");
      }
      const { data, error } = await supabase
        .from("projects")
        .insert({ user_id: userId, slug, ...fields })
        .select()
        .single();
      if (error) fail("Failed to insert project", error);
      return ok({ success: true, project: data, action: "inserted" });
    },
  );

  // -------------------------------------------------------------------------
  // WORK ITEMS
  // -------------------------------------------------------------------------

  server.tool(
    "add_work_item",
    "Add a work item (issue/task) to a project. external_id is the Linear/Jira reference like 'EID-47' or 'OCE-110'. Use status='deferred' for backlog items you want to remember but not act on now (the structured replacement for projects.json deferred_followups).",
    {
      project_slug: z.string().describe("Project slug"),
      title: z.string().describe("Short title of the work item"),
      external_id: z
        .string()
        .optional()
        .describe("Linear/Jira ID, e.g. 'EID-47'"),
      status: z
        .enum([
          "backlog",
          "todo",
          "in_progress",
          "in_review",
          "completed",
          "canceled",
          "deferred",
        ])
        .optional()
        .describe("Defaults to 'todo'"),
      priority: z.enum(["low", "medium", "high"]).optional(),
      pr_urls: z
        .array(z.string())
        .optional()
        .describe("URLs of associated PRs/MRs"),
      notes: z.string().optional(),
      blocked_by: z
        .string()
        .optional()
        .describe(
          "Free-text reason this is blocked, e.g. 'infra provisioning'",
        ),
    },
    async ({
      project_slug,
      title,
      external_id,
      status,
      priority,
      pr_urls,
      notes,
      blocked_by,
    }) => {
      const project_id = await resolveProjectId(project_slug);
      const { data, error } = await supabase
        .from("work_items")
        .insert({
          user_id: userId,
          project_id,
          title,
          external_id: external_id || null,
          status: status || "todo",
          priority: priority || null,
          pr_urls: pr_urls || [],
          notes: notes || null,
          blocked_by: blocked_by || null,
        })
        .select()
        .single();
      if (error) fail("Failed to add work item", error);
      return ok({ success: true, work_item: data });
    },
  );

  server.tool(
    "update_work_item",
    "Update a work item's status or fields. Identify it by external_id (preferred when available) plus project_slug, or by id (UUID). Status transitions to 'completed' auto-stamp completed_at. Pass null for notes/blocked_by/pr_urls to clear them.",
    {
      project_slug: z
        .string()
        .optional()
        .describe("Required when using external_id"),
      external_id: z
        .string()
        .optional()
        .describe("Linear/Jira ID, e.g. 'EID-47'"),
      id: z
        .string()
        .optional()
        .describe("UUID of the work item (use when external_id is not set)"),
      status: z
        .enum([
          "backlog",
          "todo",
          "in_progress",
          "in_review",
          "completed",
          "canceled",
          "deferred",
        ])
        .optional(),
      priority: z.enum(["low", "medium", "high"]).optional(),
      pr_urls: z
        .array(z.string())
        .nullable()
        .optional()
        .describe("Replaces the existing list; pass null or [] to clear"),
      notes: z.string().nullable().optional(),
      blocked_by: z.string().nullable().optional(),
      title: z.string().optional(),
    },
    async ({ project_slug, external_id, id, pr_urls, ...fields }) => {
      if (!id && !(external_id && project_slug)) {
        throw new Error("Provide either id, or (external_id + project_slug)");
      }
      const updates: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(fields)) {
        if (v !== undefined) updates[k] = v;
      }
      // pr_urls: undefined means leave alone, null means clear to [], array
      // means replace. Storing [] rather than NULL keeps array operations safe.
      if (pr_urls !== undefined) {
        updates.pr_urls = pr_urls === null ? [] : pr_urls;
      }
      if (Object.keys(updates).length === 0) {
        throw new Error("No fields provided to update");
      }

      let q = supabase.from("work_items").update(updates).eq("user_id", userId);
      if (id) {
        q = q.eq("id", id);
      } else {
        const project_id = await resolveProjectId(project_slug!);
        q = q.eq("project_id", project_id).eq("external_id", external_id!);
      }
      const { data, error } = await q.select().single();
      if (error) fail("Failed to update work item", error);
      return ok({ success: true, work_item: data });
    },
  );

  server.tool(
    "list_work_items",
    "List work items, optionally filtered by project and/or status. Use status='deferred' to see the deferred-followups backlog. Use status='in_review' to find open PRs awaiting review.",
    {
      project_slug: z
        .string()
        .optional()
        .describe("Restrict to a single project"),
      status: z
        .enum([
          "backlog",
          "todo",
          "in_progress",
          "in_review",
          "completed",
          "canceled",
          "deferred",
        ])
        .optional(),
      has_pr: z
        .boolean()
        .optional()
        .describe("If true, only return items with at least one pr_url"),
      limit: z.number().optional().describe("Max rows (default: 100)"),
    },
    async ({ project_slug, status, has_pr, limit }) => {
      let q = supabase
        .from("work_items")
        .select(
          "id, project_id, external_id, title, status, priority, pr_urls, notes, blocked_by, completed_at, updated_at",
        )
        .eq("user_id", userId);
      if (project_slug) {
        const project_id = await resolveProjectId(project_slug);
        q = q.eq("project_id", project_id);
      }
      if (status) q = q.eq("status", status);
      // Filter pr_urls in SQL using PostgREST's neq against an empty array
      // literal — `{}`. Pushing this server-side prevents has_pr+limit from
      // silently dropping items.
      if (has_pr) q = q.neq("pr_urls", "{}");
      const { data, error } = await q
        .order("updated_at", { ascending: false })
        .limit(limit ?? 100);
      if (error) fail("Failed to list work items", error);
      return ok({ count: data?.length ?? 0, work_items: data });
    },
  );

  // -------------------------------------------------------------------------
  // DECISIONS
  // -------------------------------------------------------------------------

  server.tool(
    "log_decision",
    "Capture a durable workflow/architectural decision, gotcha, or preference. Use this instead of writing a feedback_*.md memory file. Omit project_slug for a global rule (e.g. 'always open draft PR after first push'). Insert + supersede happens atomically in one DB call.",
    {
      title: z.string().describe("Short headline"),
      body: z.string().describe("The decision/rule itself"),
      rationale: z
        .string()
        .optional()
        .describe("Why — often a past incident or strong preference"),
      applies_to: z.string().optional().describe("When/where this kicks in"),
      project_slug: z
        .string()
        .optional()
        .describe("Project scope; omit for global"),
      category: z
        .enum([
          "workflow",
          "architecture",
          "gotcha",
          "preference",
          "convention",
        ])
        .optional(),
      tags: z.array(z.string()).optional(),
      supersedes_id: z
        .string()
        .optional()
        .describe(
          "UUID of an older decision this replaces — that decision will be marked superseded in the same transaction",
        ),
    },
    async ({
      title,
      body,
      rationale,
      applies_to,
      project_slug,
      category,
      tags,
      supersedes_id,
    }) => {
      const project_id = project_slug
        ? await resolveProjectId(project_slug)
        : null;
      const { data, error } = await supabase.rpc("pt_insert_decision", {
        p_user_id: userId,
        p_project_id: project_id,
        p_title: title,
        p_body: body,
        p_rationale: rationale ?? null,
        p_applies_to: applies_to ?? null,
        p_category: category ?? null,
        p_tags: tags ?? [],
        p_supersedes_id: supersedes_id ?? null,
      });
      if (error) fail("Failed to log decision", error);
      return ok({ success: true, decision: data });
    },
  );

  server.tool(
    "list_decisions",
    "Search decisions by project, category, or tag. Returns only non-superseded entries unless include_superseded=true.",
    {
      project_slug: z
        .string()
        .optional()
        .describe(
          "Restrict to a project. Omit to include global decisions too.",
        ),
      only_global: z
        .boolean()
        .optional()
        .describe("If true, return only decisions with no project_id"),
      category: z
        .enum([
          "workflow",
          "architecture",
          "gotcha",
          "preference",
          "convention",
        ])
        .optional(),
      tag: z.string().optional().describe("Match against the tags array"),
      include_superseded: z.boolean().optional(),
    },
    async ({
      project_slug,
      only_global,
      category,
      tag,
      include_superseded,
    }) => {
      let q = supabase
        .from("project_decisions")
        .select("*")
        .eq("user_id", userId);
      if (only_global) {
        q = q.is("project_id", null);
      } else if (project_slug) {
        const project_id = await resolveProjectId(project_slug);
        q = q.eq("project_id", project_id);
      }
      if (category) q = q.eq("category", category);
      if (tag) q = q.contains("tags", [tag]);
      if (!include_superseded) q = q.is("superseded_by", null);
      const { data, error } = await q.order("created_at", { ascending: false });
      if (error) fail("Failed to list decisions", error);
      return ok({ count: data?.length ?? 0, decisions: data });
    },
  );

  // -------------------------------------------------------------------------
  // REFERENCES
  // -------------------------------------------------------------------------

  server.tool(
    "set_reference",
    "Upsert a key/value reference (e.g. Linear team ID, GitLab namespace, deploy script path). Project-scoped if project_slug is provided, global otherwise. Replaces the old reference_*.md files.",
    {
      key: z
        .string()
        .describe(
          "Reference key, e.g. 'linear_team_id', 'gitlab_namespace_data_pipelines'",
        ),
      value: z.string().describe("The value to store"),
      description: z
        .string()
        .optional()
        .describe("What this is and when to use it"),
      project_slug: z
        .string()
        .optional()
        .describe("Project scope; omit for global"),
    },
    async ({ key, value, description, project_slug }) => {
      const project_id = project_slug
        ? await resolveProjectId(project_slug)
        : null;

      // Manual upsert: PostgREST .upsert() can't target partial unique indexes.
      let lookup = supabase
        .from("project_references")
        .select("id")
        .eq("user_id", userId)
        .eq("key", key);
      lookup = scopeByProject(lookup, project_id);
      const existing = await lookup.maybeSingle();
      if (existing.error) fail("Failed to look up reference", existing.error);

      if (existing.data) {
        const { data, error } = await supabase
          .from("project_references")
          .update({ value, description: description ?? null })
          .eq("id", existing.data.id)
          .select()
          .single();
        if (error) fail("Failed to update reference", error);
        return ok({ success: true, reference: data, action: "updated" });
      }
      const { data, error } = await supabase
        .from("project_references")
        .insert({
          user_id: userId,
          project_id,
          key,
          value,
          description: description ?? null,
        })
        .select()
        .single();
      if (error) fail("Failed to insert reference", error);
      return ok({ success: true, reference: data, action: "inserted" });
    },
  );

  server.tool(
    "list_references",
    "List references for a project (or globally). Useful when looking up IDs/URLs/paths you've previously saved.",
    {
      project_slug: z
        .string()
        .optional()
        .describe("Restrict to a project. Omit to include global refs too."),
      only_global: z.boolean().optional(),
      key_prefix: z
        .string()
        .optional()
        .describe("Filter keys starting with this prefix"),
    },
    async ({ project_slug, only_global, key_prefix }) => {
      let q = supabase
        .from("project_references")
        .select("*")
        .eq("user_id", userId);
      if (only_global) {
        q = q.is("project_id", null);
      } else if (project_slug) {
        const project_id = await resolveProjectId(project_slug);
        q = q.eq("project_id", project_id);
      }
      if (key_prefix) q = q.ilike("key", `${key_prefix}%`);
      const { data, error } = await q.order("key");
      if (error) fail("Failed to list references", error);
      return ok({ count: data?.length ?? 0, references: data });
    },
  );

  // -------------------------------------------------------------------------
  // NEXT STEPS
  // -------------------------------------------------------------------------

  server.tool(
    "set_next_steps",
    "Replace a project's pending next-steps list with the provided ordered array, atomically (delete + insert in one DB transaction). Completed/historical steps are preserved. Pass an empty array to clear the active list.",
    {
      project_slug: z.string(),
      steps: z
        .array(z.string())
        .describe("Ordered list of next-step descriptions"),
    },
    async ({ project_slug, steps }) => {
      const project_id = await resolveProjectId(project_slug);
      const { data, error } = await supabase.rpc(
        "pt_replace_active_next_steps",
        {
          p_user_id: userId,
          p_project_id: project_id,
          p_steps: steps,
        },
      );
      if (error) fail("Failed to replace next steps", error);
      return ok({ success: true, project_slug, steps: data ?? [] });
    },
  );

  server.tool(
    "complete_next_step",
    "Mark a next step complete. Identify by id (UUID) or by exact step text (within the project).",
    {
      project_slug: z.string().describe("Project slug"),
      id: z.string().optional().describe("UUID of the step"),
      step: z.string().optional().describe("Exact step text to match"),
    },
    async ({ project_slug, id, step }) => {
      if (!id && !step) throw new Error("Provide either id or step text");
      const project_id = await resolveProjectId(project_slug);
      let q = supabase
        .from("project_next_steps")
        .update({ completed_at: new Date().toISOString() })
        .eq("user_id", userId)
        .eq("project_id", project_id)
        .is("completed_at", null);
      if (id) q = q.eq("id", id);
      else q = q.eq("step", step!);
      const { data, error } = await q.select();
      if (error) fail("Failed to complete next step", error);
      if (!data || data.length === 0) {
        throw new Error("No matching active next step found");
      }
      return ok({ success: true, completed: data });
    },
  );

  const transport = new StreamableHTTPTransport({
    sessionIdGenerator: undefined,
    enableJsonResponse: true,
  });
  await server.connect(transport);
  return transport.handleRequest(c);
});

// Health check
app.get("*", (c) =>
  c.json({ status: "ok", service: "Project Tracker", version: "0.1.0" }),
);

Deno.serve(app.fetch);
