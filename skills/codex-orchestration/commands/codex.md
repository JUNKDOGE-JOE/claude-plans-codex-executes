---
description: Delegate one implementation task to a Codex worker (Sol / Luna / Terra = GPT-5.6 variants; default Sol), then review its diff
argument-hint: <task description> [--worker sol|luna|terra]
---

You are the orchestrator (Fable 5). Delegate this implementation task to a Codex worker, then review what it did. Do NOT implement it yourself.

Rule on this machine: **Fable plans → Sol / Luna / Terra execute → Fable accepts.**
The three workers are the GPT-5.6 model variants (`gpt-5.6-sol`, `gpt-5.6-luna`, `gpt-5.6-terra`), all reachable through the Codex CLI login. Default single-task worker is **Sol**.

**Exception — do not delegate shader work.** If the task is shader authoring (DynamicFX `@dynamicfx` shaders, GLSL, Shadertoy ports, `examples/*.glsl`, shader compile/visual debugging, the live-AE iteration loop), stop here and do it yourself on Fable; tell the user why.

Task to delegate:
$ARGUMENTS

Steps:

1. **Understand & scope.** Read the relevant files so you can write a precise brief. If the task is ambiguous or too large for one delegation, stop and ask the user — or split it and suggest `/codex-fanout`.

2. **Write a structured brief** to `.codex/brief.md` (Write tool; the wrapper creates the directory and self-gitignores it) with these sections:
   - `## 任务` — one clear sentence of what to build/change.
   - `## 背景与相关文件` — concrete file paths and existing patterns to follow. The worker cannot see this conversation: embed every repo-specific rule the task touches (e.g. the repo's CLAUDE.md governance — for DynamicFX the ADR / evidence / "no new persistent field without an ADR" rules), and tell it to use the Codex skill `$comment-discipline` for any comments it writes.
   - `## 约束` — follow existing style / local helper APIs; do not touch unrelated code; **do not commit**.
   - `## 验收标准` — verifiable outcomes + the exact test commands to run.
   - `## 完成后` — "总结你改了哪些文件、为什么、如何验证(跑了什么、结果如何;跑不了的如实写「未运行」)。"

3. **Pick worker + effort.**
   - Worker: `sol` by default. `terra` / `luna` when Sol is already busy on another task, or when you want a second variant's take on the same brief.
   - Effort: `medium` default; `high` / `xhigh` for hard tasks; `max` for the hardest; `ultra` only on Sol/Terra (Luna caps at `max`). Effort is the main cost lever — raise it deliberately.
   - Cheap mechanical work (rename / boilerplate / formatting) may still go to `-Model gpt-5.4-mini` or `gpt-5.3-codex-spark` explicitly.

4. **Delegate** via the wrapper (PowerShell; it lives in the user config dir, so this works in every repo):
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\codex-run.ps1" -BriefFile .codex/brief.md -Worker sol -Effort medium
   ```
   (`-Worker` maps to `-Model gpt-5.6-<worker>`; pass `-Model` explicitly to override. Add `-Cwd <repo>` when not already in the repo root.)
   It prints the worker's exit code and final result message.

5. **Review (mandatory before accepting).**
   - `git status` + `git diff` to see exactly what changed.
   - Check changes against the acceptance criteria; run the tests yourself — worker "I ran the tests" claims are untrusted (the sandbox usually cannot run test runners / spawn pwsh). A worker that declares itself environment-blocked exits 0 with no diff — retry once in a fresh session before doing it yourself.
   - For non-trivial diffs, use `/code-review` (or superpowers `requesting-code-review` if that plugin is installed).

6. **Decide.**
   - Good → tell the user what the worker changed and that you reviewed it. You commit (only when the user asks for a commit); workers cannot (worktree git metadata lives outside their sandbox).
   - Issues → iterate in the SAME Codex session (same worker):
     ```powershell
     pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\codex-run.ps1" -Resume -Brief "<具体修改意见>" -Worker sol
     ```
     (`-Resume` picks the last session for the current cwd; pass `-SessionId <id>` to pin one, and `-BriefFile` for long feedback.)
   - Never accept changes you have not reviewed.

_Full rules, brief template and the battle-tested worker traps live in the skill `codex-orchestration` (`~/.claude/skills/codex-orchestration/`, see `references/`)._
