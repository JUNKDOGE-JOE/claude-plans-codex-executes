---
description: Run several INDEPENDENT implementation tasks in parallel on the Sol / Luna / Terra workers (GPT-5.6 variants), each in its own git worktree
argument-hint: <goal, or a list of independent tasks>
---

You are the orchestrator (Fable 5). Fan out INDEPENDENT implementation tasks to the parallel Codex workers **Sol, Luna, Terra** (the three GPT-5.6 variants), each isolated in its own git worktree, then review and integrate.

Rule on this machine: **Fable plans → Sol / Luna / Terra execute → Fable accepts.**

**Exception — shader work is all-Fable.** Shader authoring tasks (DynamicFX `@dynamicfx` shaders, GLSL, Shadertoy ports, `examples/*.glsl`, shader debugging) are never fanned out; keep them for yourself and fan out only the non-shader tasks.

Goal / tasks:
$ARGUMENTS

Steps:

1. **Decompose** into 2–3 tasks that are truly independent (no shared files, no ordering between them) — one per worker. If there are more than 3 independent tasks, queue the extras onto whichever worker finishes first. If they are not independent, say so and use `/codex` sequentially instead. Confirm the breakdown with the user before spawning multiple workers.

2. **Assign workers in this order**: task 1 → `sol`, task 2 → `terra`, task 3 → `luna`. Each worker runs its namesake model (`gpt-5.6-sol` / `gpt-5.6-terra` / `gpt-5.6-luna`). Pick effort per task (`medium` default; `high`/`xhigh` hard; `max` hardest; `ultra` only Sol/Terra).

3. **Per task, create an isolated worktree + branch** (from repo root), named after the repo and the worker:
   ```powershell
   git worktree add ../<repo>-codex-<worker> -b codex/<worker>-<taskid>
   ```
   Worktrees lack untracked files from the main checkout (plans, node_modules, design exports, local CLAUDE.md) — copy or embed everything the worker needs into `<worktree>/.codex/`, and give every brief an explicit "don't touch" file list so the three diffs cannot collide. **Never junction the main checkout's `node_modules` into a worktree while a worker runs there** — a worker's `npm ci` follows the junction and empties the main checkout.

4. **Write each task's brief** into its own `<worktree>/.codex/brief.md` (same brief structure as `/codex`, including the repo-specific rules and `$comment-discipline`).

5. **Launch each worker in the background** (PowerShell tool with run_in_background), pointing it at its worktree:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\codex-run.ps1" -BriefFile <worktree>/.codex/brief.md -Cwd <worktree> -Worker <worker> -Effort <effort>
   ```

6. **Collect** — wait for all workers to finish (you will be notified). Read each result text, not just the exit code (a worker that declares itself environment-blocked exits 0 with no diff — retry once in a fresh session before doing it yourself). If a completion notice never arrives, read `<worktree>/.codex/result-*.md` directly and kill leftover `codex` / `node` processes before removing the worktree.

7. **Review each worktree's diff** (`git -C <worktree> diff`) against its acceptance criteria. Mandatory. Run the suites yourself per worktree with a hard timeout (worker-authored async tests have hung `node --test` before); for copy/vendor tasks byte-compare against the source artifact.

8. **Integrate** good ones back: commit on each `codex/<worker>-<taskid>` branch when the user has asked for commits (workers cannot commit from the sandbox), then merge or cherry-pick into the target branch — one integration branch for all three is usually simpler than three PRs. For failures, iterate with `-Resume -Cwd <worktree> -Worker <worker>`. Clean up when done: `git worktree remove <worktree>` (detach any junction first).

Keep parallelism to the three named workers and only for genuinely independent work.

_Full rules, brief template and the battle-tested worker traps live in the skill `codex-orchestration` (`~/.claude/skills/codex-orchestration/`, see `references/`)._
