---
name: codex-dispatch
description: Dispatch execution work to headless Codex (gpt-5.6 sol/terra/luna) as subagents and consume structured JSON receipts. Use whenever work in this repo requires exploration, implementation, debugging, code review, or hardware acceptance — i.e. anything beyond deciding what should happen. Also use when the user says "派给 codex", "开一条线", "拉 codex", or asks about model/effort tier selection.
---

# Codex Dispatch

Claude is the **decision layer**. Codex is the **execution layer**. Claude's context budget is
scarce; Codex's is not. Every token Codex spends on exploration and implementation is a token
Claude does not spend.

## Role boundary — non-negotiable

| Layer | Owner | Does | Must not do |
|---|---|---|---|
| L0 | User | Product direction, priority calls, acceptance sign-off | — |
| L1 | Claude | Intent → task brief, tier selection, read receipts, course-correct, block scope creep | Write implementation code, explore the repo broadly, restate long Codex output |
| L2 | Codex | Recon, implement, test, review, hardware acceptance | Change priorities, widen scope, open the next package unasked |

**Claude does not write implementation code and hand it to Codex to transcribe.** Having write
access is not a licence to use it. Claude produces *constraints and acceptance criteria*; Codex
produces *diffs*. If a reply is drifting toward pasting code, the task brief was underspecified —
rewrite the brief, do not write the patch.

**Verification exception (the only carve-out):** Claude may read up to 3 files, specific line
ranges only, solely to spot-check a claim in a receipt. No broad reads, no repo-wide grep. Without
this, receipts drift toward optimism and no one notices.

**Steady-state reply length:** ≤ 40 lines. Longer means Claude is doing L2 work.

## Invocation

The binary ships inside the desktop app and is **not on PATH**:

```
/Applications/ChatGPT.app/Contents/Resources/codex
```

Every call needs `dangerouslyDisableSandbox: true` — Codex writes session state to `~/.codex`,
which the Bash sandbox denies. Symptom if forgotten:
`failed to initialize in-process app-server client: Operation not permitted (os error 1)`.

Always redirect stdin from `/dev/null`, or Codex blocks on "Reading additional input from stdin".
`timeout` is not available on this host — do not wrap calls in it.

```bash
/Applications/ChatGPT.app/Contents/Resources/codex exec \
  -m gpt-5.6-terra \
  -c model_reasoning_effort='"high"' \
  -c approval_policy='"never"' \
  -s workspace-write \
  -C <worktree> \
  --output-schema <skill-dir>/receipt.schema.json \
  -o <scratchpad>/r-<id>.json \
  "<task brief>" < /dev/null
```

Then read **only** `r-<id>.json`. Never pipe the full transcript back into context; `tail -3` at
most, to confirm the process ended.

Long-running lines: launch with `run_in_background: true` and stop thinking about them. The harness
re-invokes on exit. Do not poll.

**Do not double-background.** `run_in_background: true` *plus* a trailing `&` kills the Codex child
when the wrapper's last foreground statement returns — the harness reports exit 0 and no receipt is
ever written. Use the harness flag alone. For the same reason, never send a dispatch to
`> /dev/null 2>&1`: a failed line then leaves no trace at all. Pipe to `tail -3` instead, so a
crash is visible without the transcript entering context.

A missing receipt file is the signal that the line died, not that it is still running. Check the
receipt path before assuming progress.

### Flags that matter

- `-s read-only` for recon lines; `-s workspace-write` for build lines.
- `-c approval_policy='"never"'` is **required** for unattended writes, otherwise the run hangs.
  The user's global config sets `approvals_reviewer = "guardian_subagent"`; override per call
  rather than editing their global config.
- `--ephemeral` skips session persistence — use it for one-shot recon. **Omit it on any line that
  may need follow-up**, because `codex exec resume <session-id>` (the equivalent of messaging a
  subagent) requires a persisted session.
- `--add-dir` for extra writable roots; `--skip-git-repo-check` outside a repo.

## Tier selection: model × effort

Pick the model by task *nature*, not by caution — Codex budget is not a constraint.

| Model | Use when | Typical |
|---|---|---|
| `gpt-5.6-luna` | The solution is known; this is typing | run tests, format, apply a specified edit, collect logs, generate reports |
| `gpt-5.6-terra` | Scope is clear but judgement is needed | write a handler, fix a reproduced bug, write tests, single-module review |
| `gpt-5.6-sol` | A hypothesis must be formed and tested | cross-layer design, new AEGP primitive, root-cause of a strange bug, hardware acceptance orchestration |

Then pick effort separately:

| Effort | When |
|---|---|
| `low` | luna default — mechanical work |
| `medium` | terra default — ordinary implementation |
| `high` | sol default; terra when debugging |
| `xhigh` | genuinely hard root-cause or cross-layer design; sol only |
| `max` | requires explicit user approval each time |
| **`ultra`** | **BANNED. Never pass it.** |

**Why `ultra` is banned:** at that tier Codex spawns its own sub-agents, which spawn theirs —
unbounded nesting, unbounded cost, and a run no one can supervise or interrupt cleanly. `sol` and
`terra` both expose `ultra`; `luna` tops out at `max`. There is no task in this repo that justifies
it. If a task seems to need `ultra`, the task is too big — split it.

## Task brief format

```
TASK <id> | tier: <model>/<effort> | mode: recon|build|review|accept
GOAL:         one sentence, user-visible outcome
DONE-WHEN:    2-4 executable criteria
NON-GOALS:    3-5 things explicitly not to do
CONSTRAINTS:  worktree, branch, paths that must not be touched
BUDGET:       turns / commits / review rounds
STOP-AND-ASK: conditions that must halt the run and report
RETURN:       emit the required JSON schema only
```

`NON-GOALS` and `STOP-AND-ASK` are load-bearing. This repo has a documented history of a single
infrastructure feature generating eleven consecutive hardening commits because neither field
existed. Omitting them is how that recurs.

## Receipt

Enforced by `receipt.schema.json`, so the shape cannot be negotiated away by the model:

`result` · `what_works` · `evidence` · `changed{files,lines,new_deps}` · `deviations` ·
`done_when[{item, status, evidence}]` · `discovered[{item, class, reproduced, instances}]` ·
`cost` · `next_decision[{question, options, recommendation}]`

Four fields carry the governance load, each added after a specific receipt failed to surface
something real:

- `discovered[].class` forces every finding into `blocker` / `follow-up` / `out-of-scope`.
- `discovered[].reproduced` is required and boolean. **An unreproduced finding cannot be a
  blocker.** This is the review-budget gate, enforced at the schema layer instead of by
  documentation nobody reads.
- `discovered[].instances` merges repeated occurrences of one root cause into a single entry with
  a count. Without it, one sandbox permission error was reported as ten separate blockers, which
  falsely trips the "three or more blockers means scope never froze" tripwire below.
- `done_when[]` requires one entry per numbered DONE-WHEN item, in order, including unmet ones,
  each with item-specific evidence. Without it, a receipt claimed three defects repaired when one
  was misdiagnosed and a required determination was never made. Where an item asked for a
  judgement, the judgement goes in `evidence` verbatim — not a claim that it was reached.

`next_decision` is capped at 2 and each entry must carry options plus a recommendation, so Claude
can rule without re-reading the code.

A finding that appears only in a produced document is not reported. Anything substantive written
into an artifact must also appear in `discovered` — a threat model once recorded a real defect in
its prose while its receipt showed no findings at all.

## Concurrency

- Parallel: 1 build line (owns a worktree) + N recon lines (read-only) + 1 review line (frozen diff).
- Never parallel: two build lines against the same worktree or the same After Effects instance.
- Hardware acceptance is always WIP=1 regardless of available budget. Unlimited budget does not
  make a single AE instance re-entrant.

## Course-correction triggers

Read straight off the receipt — intervene when any fires:

| Signal | Reading | Action |
|---|---|---|
| `cost` over budget | brief was too vague | rewrite and relaunch, do not extend |
| ≥3 `blocker` in `discovered` | scope never froze | re-cut the task package |
| `changed.lines` > 3× expected | scope creep | review the diff before anything merges |
| `what_works` unchanged across 2 receipts | spinning | change tier or change the cut |
| `deviations` non-empty without a stop-and-ask | contract violated | tighten CONSTRAINTS next brief |

## State

`docs/BOARD.md`, hard cap 60 lines, updated by Codex at the end of each package: active line ·
WIP ownership · frozen decisions · decisions awaiting the user. Claude reads only this at session
start.

**This skill does not belong in `AGENTS.md` and must never be added to `REQUIRED_RULES` in
`scripts/check-repository-governance.mjs`.** That array is a one-way ratchet: entries can be added
but never removed without breaking CI, which is precisely how the repository's governance grew
from 130 to 217 lines and 13 to 41 locked assertions in three days. This is a working agreement,
revisable at any time — not a constitution.
