# Oceanum App Scaffolding

Project templates the `pa-developer` subagent uses to scaffold new Oceanum PRAX
applications. See [`SKILL.md`](SKILL.md) for the activation contract and the
variable-substitution process.

## Contents

```
templates/
  eidos_app_template/        EIDOS frontend app (Vite + React + TS, PRAX deploy)
  prax_fullstack_template/   React frontend + FastAPI backend (full-stack PRAX)
```

Each template includes a `TEMPLATE_INFO.md` listing its `{{VARIABLE}}`
placeholders and instantiation notes.

## Origin

Relocated from `work-assistant/agents/developer/templates/` when the file-based
personal-assistant scaffolding was consolidated into Open Brain. Oceanum-specific;
local skill pack (not intended for upstream OB contribution as-is).
