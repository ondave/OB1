---
name: oceanum-app-scaffolding
description: |
  Project templates for bootstrapping new Oceanum PRAX applications. Fire when
  the pa-developer subagent (or the user) needs to create a new EIDOS-based app
  or a React+FastAPI full-stack PRAX app. Provides two ready-to-instantiate
  template trees under templates/, parameterised with {{VARIABLE}} placeholders.
author: Dave Johnson
version: 0.1.0
---

# Oceanum App Scaffolding

## Problem

Creating a new Oceanum app from scratch means re-deriving the same Dockerfile,
PRAX deploy spec, Vite/React or FastAPI layout, and CI wiring every time. These
templates capture the house style so a new repo is consistent and deploy-ready.

## Templates

- **`templates/eidos_app_template/`** — an EIDOS frontend app for the PRAX
  platform (Vite + React + TypeScript, nginx, Dockerfile, `.oceanum-prax.yml`).
- **`templates/prax_fullstack_template/`** — a full-stack PRAX app: React
  frontend + FastAPI backend, docker-compose, `app-spec.yml`, CI.

## Template variables

Replace these placeholders when instantiating either template (see each
template's `TEMPLATE_INFO.md` for the authoritative list):

| Variable | Description | Example |
| -------- | ----------- | ------- |
| `{{APP_NAME}}` | Lowercase, hyphen-separated app name | `my-ocean-app` |
| `{{APP_DESCRIPTION}}` | One-line description | `Ocean current visualization` |
| `{{USER_REF}}` | User reference / namespace | `h2ocean` |
| `{{MEMBER_EMAIL}}` | Owner email | `d.johnson@oceanum.science` |

## Process

1. Pick the template that matches the app type (EIDOS frontend vs full-stack).
2. Copy the template tree to the new repo location.
3. Substitute every `{{VARIABLE}}` across all files.
4. Hand off to the `pa-developer` subagent / GitLab MCP to create the repo,
   push the scaffold, protect `main`, and wire CI. Follow the developer agent's
   repo-creation conventions (namespace verification, draft MR workflow).

## Output

A new, consistently-structured Oceanum app repository ready for PRAX deploy.

## Notes

- Oceanum/PRAX-specific — this is a local skill pack, not general-purpose OB
  community content. Keep it out of any upstream PR unless generalised.
- Complements the global `prax` and `eidos` Claude Code skills, which cover the
  spec formats; this skill provides the runnable project scaffolds.
- Relocated from `work-assistant/agents/developer/templates/` during the
  consolidation of the file-based assistant scaffolding into Open Brain.
