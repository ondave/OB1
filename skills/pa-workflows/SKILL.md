---
name: pa-workflows
description: |
  Multi-step personal-assistant routines that span several subagents. Fire when
  the user asks for a "daily standup", "start a new feature" / "kick off feature
  work from Asana", or "weekly plan" / "plan my week". Each routine names the
  subagents to invoke, the order, and the output shape. Use the main loop to
  coordinate; invoke the pa-* subagents via the Agent tool.
author: Dave Johnson
version: 0.1.0
---

# Personal Assistant Workflows

## Problem

Some assistant requests aren't a single agent's job — a standup pulls from
tasks + calendar + writing; starting a feature spans tasks + developer + email.
This skill is the orchestration layer: it says which subagents to call, in what
order, and what the combined output should look like.

## Subagents and memory

- Subagents (invoke via the Agent tool): `pa-tasks` (Asana), `pa-calendar`
  (Google Calendar), `pa-writing`, `pa-developer` (GitLab), `pa-email`,
  `pa-research`. Each is self-contained and reads its own identity/preferences.
- Shared state lives in Open Brain MCP, not files: identity/contacts/preferences
  via the **personal-assistant** recipe (`get_profile`, `get_preferences`,
  `get_contact`); durable project state via the **project-tracker** recipe.
- Save any artifacts to the current working directory unless the user says
  otherwise. There is no longer a fixed `work-assistant/*/output/` tree.

---

## Workflow 1 — Daily Standup

**Trigger:** "prepare my standup", "what did I do yesterday / what's on today".
**Subagents:** pa-tasks → pa-calendar (parallel) → pa-writing.

1. **pa-tasks** — from Asana, get: completed yesterday, in progress, planned
   today, blocked. Default workspace `oceanum` unless the user says personal.
2. **pa-calendar** — today's meetings and free focus blocks (run alongside 1).
3. **pa-writing** — compile into standup notes:

```markdown
# Daily Standup — <date>
## ✅ Completed Yesterday
## 🔄 In Progress
## 🎯 Plan for Today
## 🚫 Blockers
## 📅 Schedule
## 💡 Notes
```

Quick version: skip pa-writing and answer "completed yesterday / on today" inline.

---

## Workflow 2 — Start New Feature

**Trigger:** "start feature work from Asana", "kick off <task> in GitLab".
**Subagents:** pa-tasks → pa-developer → pa-tasks (update) → pa-email (optional).

1. **pa-tasks** — fetch the Asana task: title, description, requirements,
   acceptance criteria, priority, due date, project, labels. If the user didn't
   name a task, offer to take the highest-priority one.
2. **pa-developer** — in GitLab: create an issue (title/description/labels/due,
   link back to Asana), create branch `feature/<slug>`, optionally seed a
   `.feature-spec.md`. Follow the developer agent's repo conventions.
3. **pa-tasks** — comment the GitLab issue URL + branch back on the Asana task;
   move status to in-development.
4. **pa-email** *(optional)* — draft a short team notification with the issue,
   branch, requirements, and target date.

Success: Asana task retrieved · GitLab issue + branch created · Asana updated
with the link · team notified (if asked).

---

## Workflow 3 — Weekly Planning

**Trigger:** "plan my week", "weekly plan for next week".
**Subagents:** pa-tasks → pa-calendar (parallel) → pa-writing.

1. **pa-tasks** — next week's tasks: due this week, carried-over overdue,
   high-priority, grouped by project with estimates where available.
2. **pa-calendar** — the week's meetings, recurring commitments, free blocks,
   conflicts; flag heavy vs light days (run alongside 1).
3. **pa-writing** — produce the plan: Week Overview, Overdue Items, Top
   Priorities, Day-by-Day Plan, Task Breakdown by Project, Capacity Analysis
   (flag overcommitment + suggest deferrals), Success Metrics, Blockers, Notes.

Capacity rule of thumb: available focus = work-hours − scheduled meetings. If
planned task hours exceed that, say so and recommend deferrals.

## Output

The compiled artifact (standup notes / feature setup summary / weekly plan),
shown inline and saved to the cwd if the user wants a file.

## Notes

- These replace the old file-based `workflows/*.md` + `smart_route.sh` runner;
  orchestration is now done by the main loop invoking the pa-* subagents.
- Mind the shared Supabase quota: call `get_project_snapshot` at most once per
  project per session; don't reflexively search Open Brain at session start.
