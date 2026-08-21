---
description: Full orchestration loop — Claude plans & accepts, the Sol / Luna / Terra workers (GPT-5.6 variants) implement (single or parallel)
argument-hint: <feature or goal>
---

Run the full orchestration loop for this goal. You (Claude Code) are the PLANNER and ACCEPTOR; the Codex workers **Sol / Luna / Terra** (GPT-5.6 variants) do the implementation.

Rule of this repo: **Claude plans → Sol / Luna / Terra execute → Claude accepts.**

Work that the repo's or the user's CLAUDE.md marks as never-delegated stays with you: plan it, write it and verify it yourself, and delegate only the surrounding implementation.

Goal:
$ARGUMENTS

1. **Plan.** Understand the goal and the codebase (read the repo's CLAUDE.md / governance docs first if it has them — reading order, milestone fit, ADR checks). For anything non-trivial, produce an explicit task breakdown (the Plan agent, or a planning skill if one is installed). Decide: single task on Sol (`/codex`) or 2–3 independent tasks on Sol / Terra / Luna in parallel (`/codex-fanout`)?

2. **Confirm** the plan/breakdown, worker assignment and effort levels with the user before delegating significant work.

3. **Delegate** each task via `./.claude/scripts/codex-run.ps1 -Worker <sol|luna|terra>` (see `/codex` and `/codex-fanout` for the exact calls and the brief structure). Stay on the orchestrator side yourself; do not implement.

4. **Accept.** Review every worker diff (`git diff` + result summary) against the acceptance criteria; run the tests yourself (worker test claims are untrusted). Use `/code-review` for non-trivial changes.

5. **Iterate** on issues via `codex-run.ps1 -Resume -Worker <same worker>` (same Codex session — keeps context).

6. **Finish.** When all tasks pass review and tests are green, commit if the user asked for a commit, then summarize what changed and how it was verified. Verify before claiming done — never report a result you did not observe yourself.

_Full rules, brief template and the battle-tested worker traps live in the skill `codex-orchestration` (`.claude/skills/codex-orchestration/`, see `references/`)._
