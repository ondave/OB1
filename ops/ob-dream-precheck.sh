#!/usr/bin/env bash
# Deterministic pre-pass for the nightly dream (run by ob-dream.sh, or by hand).
# Plain SQL + shell, no model, so it behaves the same every night and can never
# leak a value through generated text.
#
#   SECRET    <table> <id> <pattern labels>   a row holding a credential-shaped string
#   DEADPATH  <slug> <path>                   a live project whose repo_paths entry is gone
#
# Only ids, table names and pattern labels are printed, never the matched text.
# Exit 0 = scan ran (findings or not); non-zero = the DB could not be queried.

set -euo pipefail

DB_CONTAINER=supabase_db_OB1

psql_q() {
  docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -At -F $'\t' -v ON_ERROR_STOP=1 -c "$1"
}

# Patterns are POSIX ARE (Postgres ~). Each needs a long enough tail that a
# bare prefix in prose ("sk-ant-api03-", "lin_api_...") does not match.
# URL credentials exclude <, *, $ and braces so placeholders such as
# "user:<password>@", "***REMOVED***" and "${PASS}" are not reported.
secret_sql=$(cat <<'SQL'
with pats(label, re) as (values
  ('linear',      'lin_api_[A-Za-z0-9]{30,}'),
  ('gitlab',      'glpat-[A-Za-z0-9_-]{20,}'),
  ('github',      '(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})'),
  ('anthropic',   'sk-ant-[a-z0-9]+-[A-Za-z0-9_-]{40,}'),
  ('aws',         'AKIA[0-9A-Z]{16}'),
  ('slack',       'xox[abprs]-[0-9A-Za-z-]{20,}'),
  ('google',      'AIza[0-9A-Za-z_-]{35}'),
  ('private-key', '-----BEGIN [A-Z ]*PRIVATE KEY-----'),
  ('url-creds',   '[a-z][a-z0-9+.-]*://[^[:space:]:/@<>*${}]+:[^[:space:]/@<>*${}]{8,}@')
),
rows(tbl, id, body) as (
  select 'thoughts', id::text, content || ' ' || coalesce(metadata::text, '') from thoughts
  union all select 'lessons', id::text, content || ' ' || coalesce(metadata::text, '') from lessons
  union all select 'projects', slug, row_to_json(t)::text from projects t
  union all select 'work_items', id::text, row_to_json(t)::text from work_items t
  union all select 'project_decisions', id::text, row_to_json(t)::text from project_decisions t
  union all select 'project_references', id::text, row_to_json(t)::text from project_references t
  union all select 'project_next_steps', id::text, row_to_json(t)::text from project_next_steps t
)
select tbl, id, string_agg(distinct label, ',' order by label)
from rows join pats on body ~ re
group by tbl, id
order by tbl, id;
SQL
)

psql_q "$secret_sql" | while IFS=$'\t' read -r tbl id labels; do
  [ -n "$tbl" ] && printf 'SECRET\t%s\t%s\t%s\n' "$tbl" "$id" "$labels"
done

psql_q "select slug, unnest(repo_paths) from projects where status not in ('archived','completed')" |
  while IFS=$'\t' read -r slug path; do
    [ -z "$path" ] && continue
    # repo_paths may use ~; expand it without eval.
    path_expanded="${path/#\~/$HOME}"
    [ -d "$path_expanded" ] || printf 'DEADPATH\t%s\t%s\n' "$slug" "$path"
  done
