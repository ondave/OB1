# Nightly Open Brain dream

You are running unattended from cron (`claude -p`). Nobody can answer a
question: never call AskUserQuestion and never wait for input. When unsure,
keep the memory and say so in the report. Finish in one pass. Your final
message is the report below and nothing else.

Scope: the Open Brain `thoughts` and `lessons` tables and the project-tracker
plugin tables (`projects`, `work_items`, `project_decisions`,
`project_next_steps`, `project_references`), through the local servers only:
tools named `mcp__open-brain__*` and `mcp__project-tracker__*`. Ignore the
claude.ai connectors (`mcp__claude_ai_*`) and never call their authenticate
tools. Do not touch files or git. Do not capture a breadcrumb about this run:
the report goes to the log, and a nightly capture would crowd the real
breadcrumbs out of the session-start injection.

## Hard limits (per run)

- At most 10 thought deletions and 5 merges. A merge is one replacement
  capture plus deletion of the rows it replaces; those deletions count
  toward the 10.
- At most 5 lesson retirements. Lessons are retired (`retire_lessons`),
  never deleted.
- At most 10 project-tracker changes (step completions, duplicate-step
  removals and duplicate work items cancelled, counted together).
- Nothing created or updated in the last 48 hours is touched: thoughts,
  lessons or tracker rows.
- Never delete `reference` or `person_note` thoughts. Report suspected
  duplicates among them under kept-for-review instead.
- Delete a thought only when every fact in it survives in a thought that
  stays, or in the replacement you just captured. If anything would be
  lost, keep it.
- Prefer keeping an existing row over re-capturing: a re-capture gets
  today's date and loses the original timing. Re-capture only when no
  survivor is adequate on its own, and put the original dates in the text
  (for example "Consolidated 2026-09-12 from notes dated 2026-07-01 to
  2026-07-10").
- `delete_thought` is permanent. Take ids only from `list_thoughts` or
  `search_thoughts` output, and re-read a thought in full before deleting it.

## Procedure

1. `thought_stats`: record the totals before.
2. Candidates: `list_thoughts` over the window given by the MODE line at the
   end of this prompt, skipping anything under 48 hours old. For each
   candidate, `search_thoughts` with its gist as the query (limit 5,
   threshold 0.75) to find near-duplicates and superseded versions among all
   thoughts, older ones included.
   - Exact or near-exact duplicate (same facts, same project, same state):
     keep the most complete one, or the newest if they are equal, and delete
     the rest.
   - Superseded breadcrumb (an older progress note for a project that a
     newer note fully covers): delete the older one.
   - Two thoughts that contradict each other: keep both and report them.
3. Lessons: `list_lessons` with status active, limit 100. Where two lessons
   state the same rule for the same context, `store_lesson` one merged
   version (narrowest correct scope, the newer wording, the same repo tag
   and category as the originals), then `retire_lessons` the originals.
   Retire a lesson outright only when a newer lesson contradicts it or the
   tool or repo it governs is gone. Give the justification for every
   retirement. Do not rewrite lessons for style.
4. Project tracker: `list_projects`, then `get_project_snapshot` for each
   project. The tracker has no delete tool, so pruning here means
   completing, cancelling or superseding, never removing.
   - Pending next steps: `complete_next_step` a step only when the
     project's own records show it done (a completed work item, or a
     decision or reference recording that outcome) or a thought found with
     `search_thoughts` records it done. Where two pending steps in one
     project say the same thing, keep the earlier one and drop the rest with
     `set_next_steps`, re-sending the surviving steps word for word in their
     existing order; use `set_next_steps` for nothing else. A pending step
     older than 60 days with no evidence either way: report it with its
     age, do not touch it.
   - Work items: two items in one project with the same external_id or the
     same title: keep the more complete one, or the newer if equal, and
     `update_work_item` the other to status canceled with a note
     "duplicate of <id>" appended to its existing notes. Items in progress
     or in review with no update for 60 days: report only. Never change
     completed or canceled items.
   - Decisions: report duplicate or contradictory current decisions under
     kept-for-review. Do not log or supersede: `log_decision` supersedes one
     id per call, so a merge would leave a duplicate current row.
   - Projects and references: report only. A project with no activity for
     90 days gets a proposed status (completed, paused or archived) with the
     evidence; a stale or duplicated reference gets one line.
5. `thought_stats`: record the totals after.

## Report (exactly this shape)

DREAM <date> <MODE>
thoughts: <before> -> <after> (deleted N, merged M)
lessons: active <before> -> <after> (retired K, merged J)
tracker: steps completed A, duplicate steps removed B, work items canceled C
actions:
- <one line per deletion, merge, retirement or tracker change: ids and a one-clause reason>
kept-for-review:
- <suspected duplicates, contradictions, stale steps and items, idle projects you did not touch, and why>
nothing to do: <the steps that found nothing>
