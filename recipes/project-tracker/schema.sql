-- Project Tracker — schema for tracking software projects, work items,
-- decisions, references, and next steps. Designed to replace ad-hoc
-- projects.json scaffolding and per-project memory files.

-- ---------------------------------------------------------------------------
-- Table: projects
--   One row per active/archived project. The "slug" is a stable short id
--   (e.g. 'eidos', 'oceanum-io-platform') used as the public handle.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    slug TEXT NOT NULL,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'in_progress', 'paused', 'completed', 'archived')),
    priority TEXT CHECK (priority IN ('low', 'medium', 'high')),
    deadline DATE,
    description TEXT,
    notes TEXT,
    repo_paths TEXT[] DEFAULT '{}',
    stakeholders TEXT[] DEFAULT '{}',
    tech_stack JSONB DEFAULT '{}'::JSONB,
    linear JSONB DEFAULT '{}'::JSONB,
    infrastructure JSONB DEFAULT '{}'::JSONB,
    metadata JSONB DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE (user_id, slug)
);

-- ---------------------------------------------------------------------------
-- Table: work_items
--   Granular issues / tasks per project. external_id holds the Linear/Jira
--   reference (e.g. 'EID-47', 'OCE-110') when one exists.
--   Status 'deferred' is the durable equivalent of projects.json
--   "deferred_followups" — things you want to remember but not act on now.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS work_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE NOT NULL,
    external_id TEXT,
    title TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'todo'
        CHECK (status IN ('backlog', 'todo', 'in_progress', 'in_review',
                          'completed', 'canceled', 'deferred')),
    priority TEXT CHECK (priority IN ('low', 'medium', 'high')),
    pr_urls TEXT[] DEFAULT '{}',
    notes TEXT,
    blocked_by TEXT,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- external_id should be unique per project when set (allows multiple
-- work items with NULL external_id, e.g. local-only chores).
CREATE UNIQUE INDEX IF NOT EXISTS work_items_external_id_uidx
    ON work_items (user_id, project_id, external_id)
    WHERE external_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Table: project_decisions
--   Durable workflow/architectural decisions, gotchas, and preferences.
--   project_id is nullable so global decisions (e.g. "always open draft PR")
--   can live alongside project-specific ones.
--   Replaces the old feedback_*.md files.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project_decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    rationale TEXT,
    applies_to TEXT,
    category TEXT CHECK (category IN ('workflow', 'architecture', 'gotcha',
                                       'preference', 'convention')),
    tags TEXT[] DEFAULT '{}',
    superseded_by UUID REFERENCES project_decisions(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ---------------------------------------------------------------------------
-- Table: project_references
--   Durable lookup data: Linear team IDs, GitLab namespace IDs, deploy
--   script paths, etc. project_id NULL means "global".
--   Replaces the old reference_*.md files.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project_references (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Unique per (user, project, key) when project is set, and (user, key) when global.
CREATE UNIQUE INDEX IF NOT EXISTS project_references_scoped_key_uidx
    ON project_references (user_id, project_id, key)
    WHERE project_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS project_references_global_key_uidx
    ON project_references (user_id, key)
    WHERE project_id IS NULL;

-- ---------------------------------------------------------------------------
-- Table: project_next_steps
--   Ordered, mutable list of pending actions per project. Maps directly to
--   projects.json "next_steps". position controls display order.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project_next_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE NOT NULL,
    step TEXT NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_projects_user_status
    ON projects(user_id, status);

CREATE INDEX IF NOT EXISTS idx_work_items_project_status
    ON work_items(project_id, status);

CREATE INDEX IF NOT EXISTS idx_work_items_user_status
    ON work_items(user_id, status);

CREATE INDEX IF NOT EXISTS idx_project_decisions_project
    ON project_decisions(project_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_project_decisions_user_category
    ON project_decisions(user_id, category);

CREATE INDEX IF NOT EXISTS idx_project_references_project
    ON project_references(project_id, key);

CREATE INDEX IF NOT EXISTS idx_project_next_steps_project_position
    ON project_next_steps(project_id, position)
    WHERE completed_at IS NULL;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_references ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_next_steps ENABLE ROW LEVEL SECURITY;

CREATE POLICY projects_user_policy ON projects
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY work_items_user_policy ON work_items
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY project_decisions_user_policy ON project_decisions
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY project_references_user_policy ON project_references
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY project_next_steps_user_policy ON project_next_steps
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- updated_at triggers (namespaced function to avoid colliding with other
-- extensions that define a generic update_updated_at_column())
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pt_update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_projects_updated_at ON projects;
CREATE TRIGGER update_projects_updated_at
    BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION pt_update_updated_at();

DROP TRIGGER IF EXISTS update_work_items_updated_at ON work_items;
CREATE TRIGGER update_work_items_updated_at
    BEFORE UPDATE ON work_items
    FOR EACH ROW EXECUTE FUNCTION pt_update_updated_at();

DROP TRIGGER IF EXISTS update_project_references_updated_at ON project_references;
CREATE TRIGGER update_project_references_updated_at
    BEFORE UPDATE ON project_references
    FOR EACH ROW EXECUTE FUNCTION pt_update_updated_at();

-- Auto-stamp completed_at when a work item transitions into 'completed'.
-- Fires on both INSERT and UPDATE so direct inserts with status='completed'
-- also get stamped.
CREATE OR REPLACE FUNCTION pt_work_items_stamp_completed_at()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status = 'completed' THEN
            NEW.completed_at = COALESCE(NEW.completed_at, now());
        END IF;
    ELSE -- UPDATE
        IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN
            NEW.completed_at = COALESCE(NEW.completed_at, now());
        ELSIF NEW.status <> 'completed' THEN
            NEW.completed_at = NULL;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS work_items_completed_at_insert ON work_items;
CREATE TRIGGER work_items_completed_at_insert
    BEFORE INSERT ON work_items
    FOR EACH ROW EXECUTE FUNCTION pt_work_items_stamp_completed_at();

DROP TRIGGER IF EXISTS work_items_completed_at_update ON work_items;
CREATE TRIGGER work_items_completed_at_update
    BEFORE UPDATE ON work_items
    FOR EACH ROW EXECUTE FUNCTION pt_work_items_stamp_completed_at();

-- ---------------------------------------------------------------------------
-- Transactional helpers (called via PostgREST rpc) so multi-step mutations
-- don't leave the DB in a partial state on error.
-- ---------------------------------------------------------------------------

-- Atomically replace the active (non-completed) next steps for a project.
CREATE OR REPLACE FUNCTION pt_replace_active_next_steps(
    p_user_id UUID,
    p_project_id UUID,
    p_steps TEXT[]
) RETURNS SETOF project_next_steps AS $$
DECLARE
    i INTEGER;
    step_count INTEGER;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM projects
        WHERE id = p_project_id AND user_id = p_user_id
    ) THEN
        RAISE EXCEPTION 'Project not found or access denied';
    END IF;

    DELETE FROM project_next_steps
    WHERE user_id = p_user_id
      AND project_id = p_project_id
      AND completed_at IS NULL;

    step_count := COALESCE(array_length(p_steps, 1), 0);
    FOR i IN 1..step_count LOOP
        INSERT INTO project_next_steps (user_id, project_id, step, position)
        VALUES (p_user_id, p_project_id, p_steps[i], i - 1);
    END LOOP;

    RETURN QUERY
        SELECT * FROM project_next_steps
        WHERE user_id = p_user_id
          AND project_id = p_project_id
          AND completed_at IS NULL
        ORDER BY position;
END;
$$ LANGUAGE plpgsql;

-- Atomically insert a decision and optionally mark another superseded.
CREATE OR REPLACE FUNCTION pt_insert_decision(
    p_user_id UUID,
    p_project_id UUID,
    p_title TEXT,
    p_body TEXT,
    p_rationale TEXT,
    p_applies_to TEXT,
    p_category TEXT,
    p_tags TEXT[],
    p_supersedes_id UUID
) RETURNS project_decisions AS $$
DECLARE
    v_new project_decisions;
BEGIN
    INSERT INTO project_decisions (
        user_id, project_id, title, body, rationale, applies_to, category, tags
    ) VALUES (
        p_user_id, p_project_id, p_title, p_body,
        p_rationale, p_applies_to, p_category, COALESCE(p_tags, '{}')
    )
    RETURNING * INTO v_new;

    IF p_supersedes_id IS NOT NULL THEN
        UPDATE project_decisions
        SET superseded_by = v_new.id
        WHERE id = p_supersedes_id AND user_id = p_user_id;
    END IF;

    RETURN v_new;
END;
$$ LANGUAGE plpgsql;

-- Allow the Edge Function (service_role) to call these via PostgREST rpc.
GRANT EXECUTE ON FUNCTION pt_replace_active_next_steps(UUID, UUID, TEXT[]) TO service_role;
GRANT EXECUTE ON FUNCTION pt_insert_decision(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT[], UUID) TO service_role;
