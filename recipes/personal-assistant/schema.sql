-- Personal Assistant — schema for storing identity, contacts, and per-domain
-- assistant preferences. Designed to replace the file-based profile.json,
-- contacts.json, and per-agent memory.json scaffolding that personal-assistant
-- subagents (email, calendar, tasks, research, writing, developer) used to read.

-- ---------------------------------------------------------------------------
-- Table: pa_profile
--   One row per user — the identity card an assistant needs before acting on
--   the user's behalf. Replaces memory/shared/profile.json.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pa_profile (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    display_name TEXT NOT NULL,
    email TEXT,
    role TEXT,
    company TEXT,
    timezone TEXT,
    work_hours_start TEXT,           -- e.g. '09:00'
    work_hours_end TEXT,             -- e.g. '18:00'
    work_days TEXT[] DEFAULT '{}',   -- e.g. {Monday,Tuesday,...}
    communication_style TEXT,
    current_projects TEXT[] DEFAULT '{}',
    metadata JSONB DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE (user_id)
);

-- ---------------------------------------------------------------------------
-- Table: pa_contacts
--   Lightweight CRM of people the assistant drafts to / schedules with.
--   "slug" is a stable short handle (e.g. 'john-smith'). Replaces
--   memory/shared/contacts.json.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pa_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    slug TEXT NOT NULL,
    name TEXT NOT NULL,
    role TEXT,
    email TEXT,
    phone TEXT,
    company TEXT,
    notes TEXT,
    tags TEXT[] DEFAULT '{}',
    last_contact DATE,
    metadata JSONB DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE (user_id, slug)
);

-- ---------------------------------------------------------------------------
-- Table: pa_preferences
--   Per-domain assistant settings as typed key/value rows. "domain" maps to a
--   subagent area; "value" is JSONB so a preference can be a scalar, list, or
--   object. Replaces the per-agent memory.json files.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pa_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    domain TEXT NOT NULL
        CHECK (domain IN ('email', 'calendar', 'tasks', 'research',
                          'writing', 'developer', 'general')),
    key TEXT NOT NULL,
    value JSONB NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE (user_id, domain, key)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_pa_contacts_user
    ON pa_contacts(user_id, name);
CREATE INDEX IF NOT EXISTS idx_pa_contacts_tags
    ON pa_contacts USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_pa_preferences_user_domain
    ON pa_preferences(user_id, domain);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
ALTER TABLE pa_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE pa_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE pa_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY pa_profile_user_policy ON pa_profile
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY pa_contacts_user_policy ON pa_contacts
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY pa_preferences_user_policy ON pa_preferences
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- updated_at triggers (namespaced function to avoid colliding with other
-- recipes/extensions that define a generic update_updated_at_column())
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pa_update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_pa_profile_updated_at ON pa_profile;
CREATE TRIGGER update_pa_profile_updated_at
    BEFORE UPDATE ON pa_profile
    FOR EACH ROW EXECUTE FUNCTION pa_update_updated_at();

DROP TRIGGER IF EXISTS update_pa_contacts_updated_at ON pa_contacts;
CREATE TRIGGER update_pa_contacts_updated_at
    BEFORE UPDATE ON pa_contacts
    FOR EACH ROW EXECUTE FUNCTION pa_update_updated_at();

DROP TRIGGER IF EXISTS update_pa_preferences_updated_at ON pa_preferences;
CREATE TRIGGER update_pa_preferences_updated_at
    BEFORE UPDATE ON pa_preferences
    FOR EACH ROW EXECUTE FUNCTION pa_update_updated_at();
