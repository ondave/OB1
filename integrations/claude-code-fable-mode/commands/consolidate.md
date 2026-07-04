---
description: Monthly memory consolidation — merge/retire lessons, prune duplicate thoughts, mine tool-failure logs, audit skill overlap
---

Run the periodic memory-consolidation pass. Work through all four steps and
end with the report; make no other changes.

## 1. Lessons ledger (Open Brain)

`list_lessons` (status `active`, limit 100). Then:

- **Merge near-duplicates**: where two or more lessons state overlapping
  rules, `store_lesson` one sharper merged version (keep the narrowest
  correct scope; prefer the newer wording), then `retire_lessons` the
  originals.
- **Retire stale rules**: retire a lesson only when it is contradicted by a
  newer lesson or provably obsolete (the tool/repo it governs is gone).
  State the justification for every retirement. Never delete; retire only.
- Leave everything else untouched — consolidation is pruning, not rewriting.

## 2. Thought pruning (Open Brain)

`list_thoughts` (days 45, limit 50). Delete via `delete_thought` ONLY
near-exact duplicates and superseded breadcrumbs (an older breadcrumb fully
covered by a newer one). Cap deletions at 10 per pass; when unsure, keep.

## 3. Mine the failure log

Read `~/.claude/logs/tool-failures.log` (and `.old` if present). Look for
repeated failure patterns — the same command failing the same way across
sessions. Each recurring pattern is a lesson candidate: write it as
context → mistake → rule and `store_lesson` it (category `operational`,
repo-scoped when the pattern is repo-specific).

## 4. Skills audit (report only — do NOT edit)

List `~/.claude/skills/*/SKILL.md` and plugin skills. Flag: pairs with
overlapping triggers/content, descriptions referencing skills that no longer
exist, and skills that plausibly never trigger. Propose merges/retirements
with one-line reasons — the user decides.

## Report

End with: lessons merged/retired (ids), thoughts deleted (count), new
lessons from the failure log, skill proposals. Then `capture_thought` a
one-paragraph breadcrumb summarizing the pass. If a step found nothing,
say "nothing to do" for it — do not manufacture work.
