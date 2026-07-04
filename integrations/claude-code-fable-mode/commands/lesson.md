---
description: Capture lessons from this session — atomic context→mistake→rule entries, routed to the repo or Open Brain by scope
argument-hint: [optional - a specific lesson to capture, in your own words]
---

Capture what this session should teach future sessions. If `$ARGUMENTS` is
non-empty, treat it as the raw material for one lesson; otherwise review the
session yourself.

## 1. Extract

Scan the session for genuine surprises: an assumption that was wrong, a tool
or flag that behaved unexpectedly, a rule you derived after wasted effort, a
correction from the user. Write **0–3** lessons. Zero is a valid answer —
do not manufacture lessons from routine work, and never write a session
diary.

Each lesson is atomic and self-contained, readable cold by someone who
wasn't here:

> **Context** (one line: where this applies) → **Mistake** (what actually
> went wrong) → **Rule** (the imperative to follow next time).

## 2. Route by scope

For each lesson, decide:

- **Repo-specific & operational** (this codebase's tools, layout, quirks —
  meaningful to teammates and CI):
  write a file `.claude/lessons/NNN-<slug>.md` at the repo root (create the
  directory if missing; NNN = next number). One lesson per file, ~10 lines
  max, the context→mistake→rule structure as headings or bold labels. It
  travels with the repo and gets reviewed in MRs.
- **Cross-project, architectural, or a user preference** (would matter in a
  different repo): call the `store_lesson` Open Brain tool with the lesson
  text, `category` (operational/architectural/preference), `topics`, and
  `repo` set to the origin repo slug — or omitted if truly global.
- **Genuinely both** (repo truth that also generalizes): file in the repo,
  and store the *generalized* form (strip repo-specific paths) in Open
  Brain.

## 3. Dedup before writing

- Repo route: read existing `.claude/lessons/` titles first; if one covers
  it, sharpen that file instead of adding a near-duplicate.
- Open Brain route: `search_lessons` with the lesson's rule first; if a
  match ≥ ~75% exists, either skip or store a merged, sharper version and
  `retire_lessons` the old id.

## 4. Confirm

End by listing what was written where (file paths / lesson ids), or state
"no lessons worth keeping" — and why in one line.
