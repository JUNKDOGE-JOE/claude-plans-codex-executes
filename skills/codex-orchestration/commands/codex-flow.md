---
description: Full orchestration loop — Fable plans & accepts, the Sol / Luna / Terra workers (GPT-5.6 variants) implement (single or parallel)
argument-hint: <feature or goal>
---

Run the full orchestration loop for this goal. You (Fable 5) are the PLANNER and ACCEPTOR; the Codex workers **Sol / Luna / Terra** (GPT-5.6 variants) do the implementation.

Rule on this machine: **Fable plans → Sol / Luna / Terra execute → Fable accepts.**

**Exception — shader work is all-Fable.** Shader authoring (DynamicFX `@dynamicfx` shaders, GLSL, Shadertoy ports, `examples/*.glsl`, shader debugging, the live-AE loop) is never delegated: plan it, write it and verify it yourself. Only the surrounding non-shader implementation (runtime code, tooling, tests) goes to the workers.

Goal:
$ARGUMENTS

1. **Plan.** Understand the goal and the codebase (read the repo's CLAUDE.md / governance docs first if it has them — e.g. DynamicFX requires its reading order, milestone fit and ADR checks before any implementation). For anything non-trivial, produce an explicit task breakdown (the Plan agent, or superpowers `writing-plans` if that plugin is installed). Decide: single task on Sol (`/codex`) or 2–3 independent tasks on Sol / Terra / Luna in parallel (`/codex-fanout`)?

2. **Confirm** the plan/breakdown, worker assignment and effort levels with the user before delegating significant work.

3. **Delegate** each task via `"$env:USERPROFILE\.claude\scripts\codex-run.ps1" -Worker <sol|luna|terra>` (see `/codex` and `/codex-fanout` for the exact calls and the brief structure). Stay on Fable 5 yourself; do not implement.

4. **Accept.** Review every worker diff (`git diff` + result summary) against the acceptance criteria; run the tests yourself (worker test claims are untrusted). Use `/code-review` for non-trivial changes.

5. **Iterate** on issues via `codex-run.ps1 -Resume -Worker <same worker>` (same Codex session — keeps context).

6. **Finish.** When all tasks pass review and tests are green, commit if the user asked for a commit, then summarize what changed and how it was verified. Verify before claiming done — never report a result you did not observe yourself.

_Full rules, brief template and the battle-tested worker traps live in the skill `codex-orchestration` (`~/.claude/skills/codex-orchestration/`, see `references/`)._
