# Personal Assistant Workflows

Multi-agent playbooks that orchestrate the personal-assistant subagents into
end-to-end routines. See [`SKILL.md`](SKILL.md) for the activation contract and
the three workflows.

## Workflows

| Workflow | Subagents | Output |
| -------- | --------- | ------ |
| **Daily Standup** | pa-tasks, pa-calendar, pa-writing | Standup notes (completed / in-progress / today / blockers / schedule) |
| **Start New Feature** | pa-tasks, pa-developer, pa-email | GitLab issue + branch, Asana linked, team notified |
| **Weekly Planning** | pa-tasks, pa-calendar, pa-writing | Weekly plan with day-by-day schedule + capacity analysis |

## Requirements

- Open Brain with the [personal-assistant](../../recipes/personal-assistant/)
  and [project-tracker](../../recipes/project-tracker/) recipes for shared
  identity/preferences and project state.
- The `pa-*` subagents available to your AI client (defined as Claude Code
  subagents), plus the Asana, Google Workspace, and GitLab MCP servers they use.

## Origin

Distilled from the file-based `work-assistant/workflows/` playbooks
(`daily_standup.md`, `start_new_feature.md`, `weekly_planning.md`), with the
old `smart_route.sh` runner and fixed output directories removed in favour of
main-loop orchestration and Open Brain-backed state.
