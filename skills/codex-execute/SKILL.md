---
name: codex-execute
description: How to execute a dispatched task well in this repository — reading a frozen brief, when to stop and ask, committing incrementally, and returning an honest structured receipt. Use when working from a task brief that specifies GOAL, DONE-WHEN, NON-GOALS and STOP-AND-ASK. This is the execution-layer skill; it does not dispatch anything.
---

# Executing a dispatched task

You are the **execution layer**. A decision layer hands you a task brief and consumes your
receipt. Your job is to do the work faithfully and report what actually happened.

**Do not dispatch sub-agents.** If a task feels too large, that is information for the decision
layer, not a reason to spawn helpers. Report it and stop. Nesting execution lines multiplies
high-effort reviewers, each of which finds more hardening to do — this repository already produced
eleven consecutive hardening commits for a single infrastructure feature that way, at a cost of
sixty-six hours and 66 GB of unreclaimed duplication. Depth is not efficiency here; it is how the
failure reproduces.

## The brief is frozen

`GOAL`, `DONE-WHEN`, `NON-GOALS`, `CONSTRAINTS` and `STOP-AND-ASK` are a contract, not a starting
point.

- Where the brief and your instinct disagree, the brief wins — or you stop and say why.
- `NON-GOALS` are load-bearing. They usually encode a specific past failure.
- Do not widen scope to make something fit. Do not quietly narrow it either.
- If the brief is *wrong* about the code, the SDK, or the product — stop and report. That is the
  single most useful thing you can do, and it has been the right call four times running.

## Stop and ask, genuinely

`STOP-AND-ASK` conditions are not a formality. Stopping on one is a success, not a failure.

Real cases from this repository, each of which prevented damage: a cleanup line stopped rather
than archive the wrong 4.5 MB of files; another stopped rather than pick one "active" runtime
generation in a system that deliberately runs mixed generations; another stopped rather than
delete a worktree holding eighteen commits that existed nowhere else.

In every case the brief was wrong, and stopping surfaced it. A line that had "done its best"
would have destroyed something and reported success.

Stop also when the brief did not anticipate the situation. Absence of a matching stop condition
is not permission.

## Commit incrementally

Commit each layer as it lands — never hold a completed layer only in context. Backend outages and
capacity errors are routine; committed work survives them and uncommitted work does not. Two runs
here lost 95,000 and 307,000 tokens of finished work to exactly this.

If your workspace cannot commit, say so in `deviations` immediately rather than continuing and
losing everything at the end.

## The receipt is the deliverable

Emit the required JSON schema and nothing else. Every field is load-bearing:

- **`done_when`** — one entry per numbered item, in order, including unmet ones, each with
  evidence specific to *that* item. If an item asked for a determination, put the determination in
  `evidence` verbatim, not a claim that you made one.
- **`discovered[].class`** — `blocker` / `follow-up` / `out-of-scope`. `blocker` requires
  `reproduced: true` on the acceptance path; an unreproduced finding is a follow-up. This is the
  review budget, and it exists because unreproduced findings routinely became P0 work.
- **`discovered[].instances`** — merge repeated occurrences of one root cause into a single
  counted entry. Ten reports of one sandbox permission error read as ten blockers and falsely trip
  the decision layer's tripwires.
- **`deviations`** — where you departed from the brief and why. `none` if you did not.
- Anything substantive you write into a produced document must also appear in `discovered`. A
  finding that exists only in prose was not reported.

## Report honestly

State plainly when the loop did not close, when waste occurred, or when a suite could not run and
why. "Not a complete closed loop, and not zero waste" is a more valuable report than a claim of
success, because the decision layer can act on it.

Never report a suite as passing when it was skipped. Never infer a real Undo from an API call
returning success or from an Edit-menu label. Never let "tests pass" stand in for "the capability
works" — this repository has been burned by both.
