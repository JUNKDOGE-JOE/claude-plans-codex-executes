---
description: Run several INDEPENDENT implementation tasks in parallel on the Codex worker slots (sol / terra / luna, models from the project's role config), each in its own git worktree
argument-hint: <goal, or a list of independent tasks>
---

You are the orchestrator (Claude Code, the planner / reviewer). Fan out INDEPENDENT implementation tasks to the parallel Codex worker slots **sol, terra, luna**, each isolated in its own git worktree, then review and integrate.

Rule of this repo: **the planner model plans → the Codex workers execute → the planner model accepts.**

Work that the repo's or the user's CLAUDE.md marks as never-delegated is not fanned out; keep it for yourself and fan out only the rest.

Goal / tasks:
$ARGUMENTS

Steps:

0. **Roles.** Read `.claude/codex-orchestration.json` (worker slot → Codex model map, fanout order, planner model). If it is missing — first use in this project — or the user asks to change roles, ask the user with AskUserQuestion: planner / reviewer model (current session model by default | Claude Fable 5 | Claude Opus 5 | Claude Sonnet 5 | other id) and developer / executor model(s) (Codex GPT-5.6 Sol / Terra / Luna by default | Codex `gpt-5.5` | Codex `gpt-5.4` | custom 1–3 ids in slot order sol, terra, luna); then run `pwsh -NoProfile -ExecutionPolicy Bypass -File ./.claude/skills/codex-orchestration/scripts/install.ps1 -Project . -PlannerModel <id|current> -ExecutorModels <csv>` and continue.

1. **Decompose** into 2–3 tasks that are truly independent (no shared files, no ordering between them) — one per slot. If there are more than 3 independent tasks, queue the extras onto whichever slot finishes first. If they are not independent, say so and use `/codex` sequentially instead. Confirm the breakdown with the user before spawning multiple workers.

2. **Assign slots in the configured fanout order** (default: task 1 → `sol`, task 2 → `terra`, task 3 → `luna`; each slot runs the model the config maps it to). Pick effort per task (`medium` default; `high`/`xhigh` hard; `max` hardest; `ultra` only where the model accepts it and better avoided — split instead).

3. **Per task, create an isolated worktree + branch** (from repo root), named after the repo and the slot:
   ```powershell
   git worktree add ../<repo>-codex-<slot> -b codex/<slot>-<taskid>
   ```
   Worktrees lack untracked files from the main checkout (plans, node_modules, design exports, local CLAUDE.md) — copy or embed everything the worker needs into `<worktree>/.codex/`, and give every brief an explicit "don't touch" file list so the three diffs cannot collide. **Never junction or symlink the main checkout's `node_modules` into a worktree while a worker runs there** — a worker's `npm ci` follows the link and empties the main checkout.

4. **Write each task's brief** into its own `<worktree>/.codex/brief.md` (same brief structure as `/codex`, including the repo-specific rules and `$comment-discipline`).

5. **Launch each worker in the background** (PowerShell tool with run_in_background, from the repo root), pointing it at its worktree:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File ./.claude/scripts/codex-run.ps1 -BriefFile <worktree>/.codex/brief.md -Cwd <worktree> -Worker <slot> -Effort <effort>
   ```

6. **Collect** — wait for all workers to finish (you will be notified). Read each result text, not just the exit code (a worker that declares itself environment-blocked exits 0 with no diff — retry once in a fresh session before doing it yourself). If a completion notice never arrives, read `<worktree>/.codex/result-*.md` directly and kill leftover `codex` / `node` processes before removing the worktree.

7. **Review each worktree's diff** (`git -C <worktree> diff`) against its acceptance criteria. Mandatory. Run the suites yourself per worktree with a hard timeout (worker-authored async tests have hung test runners before); for copy/vendor tasks byte-compare against the source artifact.

8. **Integrate** good ones back: commit on each `codex/<slot>-<taskid>` branch when the user has asked for commits (workers cannot commit from the sandbox), then merge or cherry-pick into the target branch — one integration branch for all three is usually simpler than three PRs. For failures, iterate with `-Resume -Cwd <worktree> -Worker <slot>`. Clean up when done: `git worktree remove <worktree>` (detach any junction first).

Keep parallelism to the three slots and only for genuinely independent work.

_Full rules, brief template and the battle-tested worker traps live in the skill `codex-orchestration` (`.claude/skills/codex-orchestration/`, see `references/`)._
