-- Lessons Ledger — a dedicated store for operational lessons learned.
--
-- Separate from `thoughts` on purpose: lessons are checkpoint-style rules
-- ("context → mistake → rule"), retrieved mechanically at session start,
-- and periodically consolidated. Mixing them into general thoughts makes
-- both retrieval and pruning worse. Additive only — does not touch the
-- core thoughts table.
--
-- Requires: pgvector (enabled by the core Open Brain setup) and the
-- update_updated_at() trigger function from docs/01-getting-started.md.

create table if not exists lessons (
  id uuid primary key default gen_random_uuid(),
  content text not null,
  embedding vector(1536),
  -- Origin repo/project slug. NULL means the lesson is global (applies everywhere).
  repo text,
  -- operational: tool/workflow rules. architectural: design decisions that
  -- transfer across projects. preference: how the user wants things done.
  category text not null default 'operational'
    check (category in ('operational', 'architectural', 'preference')),
  -- Soft retirement keeps history without polluting retrieval.
  status text not null default 'active'
    check (status in ('active', 'retired')),
  metadata jsonb default '{}'::jsonb,
  content_fingerprint text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create unique index if not exists idx_lessons_fingerprint
  on lessons (content_fingerprint) where content_fingerprint is not null;
create index if not exists lessons_created_at_idx on lessons (created_at desc);
create index if not exists lessons_embedding_idx on lessons using hnsw (embedding vector_cosine_ops);
create index if not exists lessons_metadata_idx on lessons using gin (metadata);
create index if not exists lessons_repo_idx on lessons (repo);

alter table lessons enable row level security;

create policy "Service role full access" on lessons
  using (auth.role() = 'service_role'::text);

create trigger lessons_updated_at before update on lessons
  for each row execute function update_updated_at();

-- Semantic search over active lessons. When filter_repo is given, returns
-- lessons from that repo PLUS global (repo IS NULL) lessons — a repo filter
-- should never hide a universal rule.
create or replace function match_lessons(
  query_embedding vector(1536),
  match_threshold double precision default 0.35,
  match_count integer default 5,
  filter_repo text default null
)
returns table (
  id uuid,
  content text,
  repo text,
  category text,
  metadata jsonb,
  similarity double precision,
  created_at timestamp with time zone
)
language plpgsql as $$
begin
  return query
  select
    l.id,
    l.content,
    l.repo,
    l.category,
    l.metadata,
    1 - (l.embedding <=> query_embedding) as similarity,
    l.created_at
  from lessons l
  where l.status = 'active'
    and 1 - (l.embedding <=> query_embedding) > match_threshold
    and (filter_repo is null or l.repo is null or l.repo = filter_repo)
  order by l.embedding <=> query_embedding
  limit match_count;
end;
$$;

-- Fingerprint-deduplicated insert, mirroring upsert_thought. Re-storing an
-- identical lesson refreshes it (and reactivates it if retired) instead of
-- creating a duplicate.
create or replace function upsert_lesson(p_content text, p_payload jsonb default '{}')
returns jsonb
language plpgsql as $$
declare
  v_fingerprint text;
  v_id uuid;
begin
  v_fingerprint := encode(sha256(convert_to(
    lower(trim(regexp_replace(p_content, '\s+', ' ', 'g'))),
    'UTF8'
  )), 'hex');

  insert into lessons (content, content_fingerprint, repo, category, metadata)
  values (
    p_content,
    v_fingerprint,
    nullif(p_payload->>'repo', ''),
    coalesce(nullif(p_payload->>'category', ''), 'operational'),
    coalesce(p_payload->'metadata', '{}'::jsonb)
  )
  on conflict (content_fingerprint) where content_fingerprint is not null do update
  set updated_at = now(),
      status = 'active',
      repo = coalesce(excluded.repo, lessons.repo),
      category = excluded.category,
      metadata = lessons.metadata || coalesce(excluded.metadata, '{}'::jsonb)
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'fingerprint', v_fingerprint);
end;
$$;
