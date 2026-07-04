---
name: fable-discipline
description: >-
  Disciplined plan→implement→verify→report execution loop for non-trivial
  coding work. MUST BE USED when starting any coding task that changes
  behavior: "implement", "add", "build", "fix", "debug", "refactor",
  "migrate", "optimize", "make it work", error reports, failing tests, or
  any bug investigation. Provides the decision procedures a weaker model
  needs to match frontier-model delivery: verifiable success criteria
  before code, root-cause-first debugging, minimal diffs, demonstrated
  (not claimed) completion, fresh-context review, and outcome-first
  reporting. NOT for pure Q&A, prose writing, or one-line typo fixes.
---

# Fable Discipline

You are running with extra scaffolding on purpose. The checkpoints below are
not style preferences — they move your verification earlier, where errors are
cheap. Two of them are also enforced mechanically by hooks (noted inline);
work **with** those gates, not around them.

Run the four phases in order. Do not skip a phase because the task "seems
simple" — deciding it is simple is Phase 1's job, not a reason to skip Phase 1.

## Phase 1 — PLAN (before any edit)

Produce these three items **in your response** before touching code:

1. **Success criteria as commands.** Restate the ask as 1–3 checks that can
   pass or fail, each with the literal command that proves it:
   - "Add validation" → `uv run pytest tests/test_validation.py` (tests you
     will write first)
   - "Fix the 500 on /export" → `curl -s localhost:8000/export | jq .status`
     returns `"ok"`
   If you cannot phrase the ask as a check, the ask is ambiguous — say which
   interpretations exist and pick one explicitly (or ask, if interactive).
2. **Touch list.** The files you expect to change. More than ~5 files or any
   schema/API change → state the plan and blast radius first.
3. **Prior-lesson check.** Session context contains lessons injected at
   session start (and possibly `.claude/lessons/` files in the repo). If any
   lesson matches this task, quote its rule in one line. If the task is risky
   and nothing was injected, call `search_lessons` with the task description.

## Phase 2 — IMPLEMENT

### Debugging: root cause before patch — always in this order

1. **Reproduce**: run the failing thing; paste the actual error.
2. **Localize**: name the file:line where behavior diverges from intent.
   Use logs/prints/debugger — not reading alone.
3. **Explain**: one sentence, "The bug is X because Y." If you cannot write
   that sentence, you are not done localizing — go back to step 2.
4. **Only then patch.** The patch must address Y, not the symptom.

Symptom-patch smell test — if your fix is one of these, return to step 2:
- wrapping the failure in `try/except` / `?.` / a null check
- adding a special case for the exact failing input
- retrying, sleeping, or reordering until it passes
- "fixing" the test instead of the code (unless the test is provably wrong —
  then say so with evidence)

### Editing: minimal diff

- Every changed line must trace to the ask. Adjacent cleanup, reformatting,
  drive-by refactors: mention, don't do.
- Match the file's existing style even where you'd choose differently.
- Remove only orphans **your** change created.
- Before moving on, re-read your own diff (`git diff`) and delete anything
  that fails the trace test.

## Phase 3 — VERIFY (the gate)

**Done means demonstrated.** A completion claim without a verification
command *run in this session, after the last edit*, is a false claim.
A Stop hook checks the transcript for exactly this and will bounce you back —
satisfy it by actually verifying, never by wording around it.

Checklist, in order:

1. Run the success-criteria commands from Phase 1. Paste real output — the
   actual numbers/lines, not a paraphrase.
2. Run the project's standard checks (whatever exists): tests, type check,
   lint, build.
3. If a criterion cannot be run (missing creds, no hardware), write
   **NOT VERIFIED:** plus the exact command someone else must run. Never
   substitute "should work".
4. For non-trivial changes (new feature, >2 files, anything concurrency/
   auth/data-loss adjacent): delegate a fresh-context review — spawn the
   `fresh-eyes-reviewer` agent with the diff and the original ask. It has
   none of your session's assumptions; that is the point. Address Blockers
   before reporting.

## Phase 4 — REPORT

- First sentence = the outcome: what changed and whether it is verified.
  Not the journey, not "I'll now…".
- Evidence block: the verification commands and their real output.
- Every factual claim in the report must be **audited**: it traces to
  something you ran or read this session. Claims you inferred but did not
  check get labelled as such ("inferred, not tested: …").
- Never end the turn with a promise ("next I'll wire up X") — either do X
  now or state plainly that you are stopping and why.

### Worked example (report)

Bad: "I've fixed the flaky test and improved the retry logic. Everything
should work now. Let me know if you'd like me to run the tests!"

Good: "The flake was a race in `queue.py:41` — the consumer read before the
producer's commit (root cause, not timing). Fixed by moving the read inside
the transaction. Verified: `uv run pytest tests/test_queue.py -x` → 14
passed, 20 consecutive runs clean. Not tested: behavior under multi-process
consumers (no fixture exists — command would be `pytest -m multiproc`)."

## Phase 5 — CAPTURE (30 seconds, when something surprised you)

If this task surprised you — a wrong assumption, a tool quirk, a rule you
derived the hard way — run `/lesson` (or follow its routing yourself):
repo-specific operational lessons → `.claude/lessons/` file in the repo;
cross-project/architectural/preference lessons → `store_lesson` in Open
Brain. One atomic lesson per entry: context → mistake → rule. No session
diaries.
