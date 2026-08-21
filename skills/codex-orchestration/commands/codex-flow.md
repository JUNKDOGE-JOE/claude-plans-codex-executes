---
description: Full orchestration loop — the planner model (this Claude Code session) plans & accepts, the Codex worker slots implement (single or parallel)
argument-hint: <feature or goal>
---

Run the full orchestration loop for this goal. You (Claude Code) are the PLANNER and ACCEPTOR; the Codex workers configured for this project do the implementation.

Rule of this repo: **the planner model plans → the Codex workers execute → the planner model accepts.**

Work that the repo's or the user's CLAUDE.md marks as never-delegated stays with you: plan it, write it and verify it yourself, and delegate only the surrounding implementation.

Goal:
$ARGUMENTS

0. **Roles.** Read `.claude/codex-orchestration.json`. If it is missing — first use in this project — or the user asks to change roles, ask the user with AskUserQuestion which model is the planner / reviewer (current session model by default | Claude Fable 5 | Claude Opus 5 | Claude Sonnet 5 | other id) and which Codex model(s) are the developer / executor (GPT-5.6 Sol / Terra / Luna by default | `gpt-5.5` | `gpt-5.4` | custom 1–3 ids in slot order sol, terra, luna); then run `pwsh -NoProfile -ExecutionPolicy Bypass -File ./.claude/skills/codex-orchestration/scripts/install.ps1 -Project . -PlannerModel <id|current> -ExecutorModels <csv>`. If the config names a planner model and this session runs a different one, tell the user once, then proceed.

1. **Plan.** Understand the goal and the codebase (read the repo's CLAUDE.md / governance docs first if it has them — reading order, milestone fit, ADR checks). For anything non-trivial, produce an explicit task breakdown (the Plan agent, or a planning skill if one is installed). Decide: single task on the default slot (`/codex`) or 2–3 independent tasks across the slots in parallel (`/codex-fanout`)?

2. **Confirm** the plan/breakdown, slot assignment and effort levels with the user before delegating significant work.

3. **Delegate** each task via `./.claude/scripts/codex-run.ps1 -Worker <slot>` (see `/codex` and `/codex-fanout` for the exact calls and the brief structure). Stay on the orchestrator side yourself; do not implement.

4. **Accept.** Review every worker diff (`git diff` + result summary) against the acceptance criteria; run the tests yourself (worker test claims are untrusted). Use `/code-review` for non-trivial changes.

5. **Iterate** on issues via `codex-run.ps1 -Resume -Worker <same slot>` (same Codex session — keeps context).

6. **Finish.** When all tasks pass review and tests are green, commit if the user asked for a commit, then summarize what changed and how it was verified. Verify before claiming done — never report a result you did not observe yourself.

_Full rules, brief template and the battle-tested worker traps live in the skill `codex-orchestration` (`.claude/skills/codex-orchestration/`, see `references/`)._
