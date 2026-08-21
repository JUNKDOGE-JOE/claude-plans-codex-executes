---
description: Delegate one implementation task to a Codex worker (slot sol / terra / luna; default from the project's role config), then review its diff
argument-hint: <task description> [--worker sol|terra|luna]
---

You are the orchestrator (Claude Code, the planner / reviewer). Delegate this implementation task to a Codex worker (the developer / executor), then review what it did. Do NOT implement it yourself.

Rule of this repo: **the planner model plans → the Codex workers execute → the planner model accepts.**

If the repo's or the user's CLAUDE.md declares work that must never be delegated and this task falls under it, stop here, do it yourself, and tell the user why.

Task to delegate:
$ARGUMENTS

Steps:

0. **Roles.** Read `.claude/codex-orchestration.json` (planner model, worker slot → Codex model map, default slot, fanout order). If it is missing — first use in this project — or the user asks to change roles, ask the user with AskUserQuestion:
   - *Planner / reviewer model*: current session model (default, not locked) | Claude Fable 5 `claude-fable-5` | Claude Opus 5 `claude-opus-5` | Claude Sonnet 5 `claude-sonnet-5` | other id.
   - *Developer / executor model(s)*: Codex GPT-5.6 Sol / Terra / Luna (default: `gpt-5.6-sol,gpt-5.6-terra,gpt-5.6-luna`) | Codex `gpt-5.5` for all slots | Codex `gpt-5.4` for all slots | custom 1–3 Codex model ids in slot order sol, terra, luna.
   Then run `pwsh -NoProfile -ExecutionPolicy Bypass -File ./.claude/skills/codex-orchestration/scripts/install.ps1 -Project . -PlannerModel <id|current> -ExecutorModels <csv>` and continue. If the config names a planner model and this session runs a different one, tell the user once (`/model`), then proceed.

1. **Understand & scope.** Read the relevant files so you can write a precise brief. If the task is ambiguous or too large for one delegation, stop and ask the user — or split it and suggest `/codex-fanout`.

2. **Write a structured brief** to `.codex/brief.md` (Write tool; the wrapper creates the directory and keeps the scratch files out of git) with these sections:
   - `## 任务` — one clear sentence of what to build/change.
   - `## 背景与相关文件` — concrete file paths and existing patterns to follow. The worker cannot see this conversation: embed every repo-specific rule the task touches (ADR / evidence policy, test gates, naming and changelog conventions, …), and tell it to use the Codex skill `$comment-discipline` for any comments it writes.
   - `## 约束` — follow existing style / local helper APIs; do not touch unrelated code; list the files it must not touch; **do not commit**.
   - `## 验收标准` — verifiable outcomes + the exact test commands to run.
   - `## 完成后` — "总结你改了哪些文件、为什么、如何验证(跑了什么、结果如何;跑不了的如实写「未运行」)。"

3. **Pick worker slot + effort.**
   - Slot: the config's default (`sol` unless changed). Another slot when the default is busy on another task, or when you want a second model's take on the same brief. Under the default mapping: hypothesis-forming work → sol, clear-scope-but-judgement work → terra, known-solution typing → luna.
   - Effort: `medium` default; `high` / `xhigh` for hard tasks; `max` for the hardest; `ultra` only where the model accepts it (GPT-5.6 Sol/Terra; Luna caps at `max`) and it makes Codex spawn its own sub-agents — split the task instead of reaching for it. Effort is the main cost lever — raise it deliberately.
   - Cheap mechanical work (rename / boilerplate / formatting) may still go to `-Model gpt-5.4-mini` or `gpt-5.3-codex-spark` explicitly without changing the config.

4. **Delegate** via the wrapper (PowerShell 7, from the repo root):
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File ./.claude/scripts/codex-run.ps1 -BriefFile .codex/brief.md -Worker sol -Effort medium
   ```
   (`-Worker` is a slot name resolved through the config; pass `-Model` explicitly to override. Add `-Cwd <dir>` when the work happens somewhere other than the repo root; `-DryRun` shows the resolved call without running it.)
   It prints the roles, the worker's exit code and its final result message.

5. **Review (mandatory before accepting).**
   - `git status` + `git diff` to see exactly what changed.
   - Check changes against the acceptance criteria; run the tests yourself — worker "I ran the tests" claims are untrusted (the sandbox usually cannot run test runners / spawn shells). A worker that declares itself environment-blocked exits 0 with no diff — retry once in a fresh session before doing it yourself.
   - For non-trivial diffs, use `/code-review`.

6. **Decide.**
   - Good → tell the user what the worker changed and that you reviewed it. You commit (only when the user asks for a commit); workers cannot (worktree git metadata lives outside their sandbox).
   - Issues → iterate in the SAME Codex session (same slot):
     ```powershell
     pwsh -NoProfile -ExecutionPolicy Bypass -File ./.claude/scripts/codex-run.ps1 -Resume -Brief "<具体修改意见>" -Worker sol
     ```
     (`-Resume` picks the last session for the current cwd; pass `-SessionId <id>` to pin one, and `-BriefFile` for long feedback.)
   - Never accept changes you have not reviewed.

_Full rules, brief template and the battle-tested worker traps live in the skill `codex-orchestration` (`.claude/skills/codex-orchestration/`, see `references/`)._
