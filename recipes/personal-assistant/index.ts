/**
 * Personal Assistant MCP Server (Remote Edge Function)
 *
 * Stores the identity, contacts, and per-domain preferences that
 * personal-assistant subagents (email, calendar, tasks, research, writing,
 * developer) need before acting on the user's behalf. Replaces the file-based
 * profile.json, contacts.json, and per-agent memory.json scaffolding.
 *
 * Tools:
 *   get_profile, set_profile
 *   list_contacts, get_contact, upsert_contact
 *   get_preferences, set_preference
 */

import { Hono } from "hono";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPTransport } from "@hono/mcp";
import { z } from "zod";
import { createClient } from "@supabase/supabase-js";

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

  const server = new McpServer({
    name: "personal-assistant",
    version: "0.1.0",
  });

  const ok = (payload: unknown) => ({
    content: [
      { type: "text" as const, text: JSON.stringify(payload, null, 2) },
    ],
  });

  // -------------------------------------------------------------------------
  // PROFILE
  // -------------------------------------------------------------------------

  server.tool(
    "get_profile",
    "Get the user's identity profile (name, role, company, work hours, timezone, work days, communication style, current projects). Read this before drafting or scheduling on the user's behalf.",
    {},
    async () => {
      const { data, error } = await supabase
        .from("pa_profile")
        .select("*")
        .eq("user_id", userId)
        .maybeSingle();
      if (error) fail("Failed to read profile", error);
      return ok({ profile: data });
    },
  );

  server.tool(
    "set_profile",
    "Create or update the user's identity profile. Pass only the fields you want to set; omitted fields are preserved on update.",
    {
      display_name: z.string().optional(),
      email: z.string().optional(),
      role: z.string().optional(),
      company: z.string().optional(),
      timezone: z.string().optional().describe("e.g. 'Pacific/Auckland'"),
      work_hours_start: z.string().optional().describe("e.g. '09:00'"),
      work_hours_end: z.string().optional().describe("e.g. '18:00'"),
      work_days: z.array(z.string()).optional(),
      communication_style: z.string().optional(),
      current_projects: z.array(z.string()).optional(),
      metadata: z.record(z.string(), z.unknown()).optional(),
    },
    async (args) => {
      const fields: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(args)) {
        if (v !== undefined) fields[k] = v;
      }
      const existing = await supabase
        .from("pa_profile")
        .select("id")
        .eq("user_id", userId)
        .maybeSingle();
      if (existing.error) fail("Failed to look up profile", existing.error);

      if (existing.data) {
        if (Object.keys(fields).length === 0) {
          const { data, error } = await supabase
            .from("pa_profile")
            .select("*")
            .eq("id", existing.data.id)
            .single();
          if (error) fail("Failed to read profile", error);
          return ok({ success: true, profile: data, action: "noop" });
        }
        const { data, error } = await supabase
          .from("pa_profile")
          .update(fields)
          .eq("id", existing.data.id)
          .select()
          .single();
        if (error) fail("Failed to update profile", error);
        return ok({ success: true, profile: data, action: "updated" });
      }

      if (!fields.display_name) {
        throw new Error("display_name is required when creating a profile");
      }
      const { data, error } = await supabase
        .from("pa_profile")
        .insert({ user_id: userId, ...fields })
        .select()
        .single();
      if (error) fail("Failed to insert profile", error);
      return ok({ success: true, profile: data, action: "inserted" });
    },
  );

  // -------------------------------------------------------------------------
  // CONTACTS
  // -------------------------------------------------------------------------

  server.tool(
    "list_contacts",
    "List saved contacts, optionally filtered by tag or company. Use when the user references a known person.",
    {
      tag: z.string().optional().describe("Return only contacts with this tag"),
      company: z.string().optional(),
    },
    async ({ tag, company }) => {
      let q = supabase
        .from("pa_contacts")
        .select("*")
        .eq("user_id", userId)
        .order("name");
      if (tag) q = q.contains("tags", [tag]);
      if (company) q = q.eq("company", company);
      const { data, error } = await q;
      if (error) fail("Failed to list contacts", error);
      return ok({ contacts: data ?? [] });
    },
  );

  server.tool(
    "get_contact",
    "Get a single contact by slug (e.g. 'john-smith').",
    { slug: z.string() },
    async ({ slug }) => {
      const { data, error } = await supabase
        .from("pa_contacts")
        .select("*")
        .eq("user_id", userId)
        .eq("slug", slug)
        .maybeSingle();
      if (error) fail("Failed to read contact", error);
      if (!data) throw new Error(`Contact not found: ${slug}`);
      return ok({ contact: data });
    },
  );

  server.tool(
    "upsert_contact",
    "Create or update a contact (matched by slug). Pass only the fields you want to set; omitted fields are preserved on update.",
    {
      slug: z.string().describe("Stable short handle, e.g. 'john-smith'"),
      name: z.string().optional(),
      role: z.string().optional(),
      email: z.string().optional(),
      phone: z.string().optional(),
      company: z.string().optional(),
      notes: z.string().optional(),
      tags: z.array(z.string()).optional(),
      last_contact: z
        .string()
        .nullable()
        .optional()
        .describe("YYYY-MM-DD, or null to clear"),
      metadata: z.record(z.string(), z.unknown()).optional(),
    },
    async ({ slug, last_contact, ...rest }) => {
      const fields: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(rest)) {
        if (v !== undefined) fields[k] = v;
      }
      if (last_contact !== undefined) fields.last_contact = last_contact;

      const existing = await supabase
        .from("pa_contacts")
        .select("id")
        .eq("user_id", userId)
        .eq("slug", slug)
        .maybeSingle();
      if (existing.error) fail("Failed to look up contact", existing.error);

      if (existing.data) {
        if (Object.keys(fields).length === 0) {
          const { data, error } = await supabase
            .from("pa_contacts")
            .select("*")
            .eq("id", existing.data.id)
            .single();
          if (error) fail("Failed to read contact", error);
          return ok({ success: true, contact: data, action: "noop" });
        }
        const { data, error } = await supabase
          .from("pa_contacts")
          .update(fields)
          .eq("id", existing.data.id)
          .select()
          .single();
        if (error) fail("Failed to update contact", error);
        return ok({ success: true, contact: data, action: "updated" });
      }

      if (!fields.name) {
        throw new Error("name is required when creating a new contact");
      }
      const { data, error } = await supabase
        .from("pa_contacts")
        .insert({ user_id: userId, slug, ...fields })
        .select()
        .single();
      if (error) fail("Failed to insert contact", error);
      return ok({ success: true, contact: data, action: "inserted" });
    },
  );

  // -------------------------------------------------------------------------
  // PREFERENCES
  // -------------------------------------------------------------------------

  const DOMAINS = [
    "email",
    "calendar",
    "tasks",
    "research",
    "writing",
    "developer",
    "general",
  ] as const;

  server.tool(
    "get_preferences",
    "Get per-domain assistant preferences. Filter by domain (e.g. 'email', 'calendar') and optionally a single key. Omit domain to return all preferences.",
    {
      domain: z.enum(DOMAINS).optional(),
      key: z.string().optional(),
    },
    async ({ domain, key }) => {
      let q = supabase
        .from("pa_preferences")
        .select("*")
        .eq("user_id", userId)
        .order("domain")
        .order("key");
      if (domain) q = q.eq("domain", domain);
      if (key) q = q.eq("key", key);
      const { data, error } = await q;
      if (error) fail("Failed to read preferences", error);
      return ok({ preferences: data ?? [] });
    },
  );

  server.tool(
    "set_preference",
    "Create or update a single preference for a domain. The value is JSON (scalar, list, or object).",
    {
      domain: z.enum(DOMAINS),
      key: z.string(),
      value: z.unknown().describe("JSON value — scalar, array, or object"),
      description: z.string().optional(),
    },
    async ({ domain, key, value, description }) => {
      const row: Record<string, unknown> = {
        user_id: userId,
        domain,
        key,
        value,
      };
      if (description !== undefined) row.description = description;

      // Manual upsert on the (user_id, domain, key) unique constraint.
      const existing = await supabase
        .from("pa_preferences")
        .select("id")
        .eq("user_id", userId)
        .eq("domain", domain)
        .eq("key", key)
        .maybeSingle();
      if (existing.error) fail("Failed to look up preference", existing.error);

      if (existing.data) {
        const update: Record<string, unknown> = { value };
        if (description !== undefined) update.description = description;
        const { data, error } = await supabase
          .from("pa_preferences")
          .update(update)
          .eq("id", existing.data.id)
          .select()
          .single();
        if (error) fail("Failed to update preference", error);
        return ok({ success: true, preference: data, action: "updated" });
      }

      const { data, error } = await supabase
        .from("pa_preferences")
        .insert(row)
        .select()
        .single();
      if (error) fail("Failed to insert preference", error);
      return ok({ success: true, preference: data, action: "inserted" });
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
  c.json({ status: "ok", service: "Personal Assistant", version: "0.1.0" }),
);

Deno.serve(app.fetch);
