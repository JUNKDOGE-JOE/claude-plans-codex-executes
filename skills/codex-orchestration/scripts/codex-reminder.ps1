#requires -Version 7
# UserPromptSubmit hook - keeps Claude anchored to the orchestration workflow across
# long sessions and context compaction. Stdout from this hook is injected into the
# model's context for the turn. Gentle nudge, not a hard block; always exits 0.
# Installed into <project>/.claude/hooks/ by the codex-orchestration skill.

# Read & discard the JSON payload on stdin so the pipe never blocks.
try { [Console]::In.ReadToEnd() | Out-Null } catch { }

Write-Output @'
[orchestration reminder] Rule of this repo: Claude plans -> Sol / Luna / Terra execute -> Claude accepts.
- You (Claude Code) are PLANNER + ACCEPTOR, not the implementer.
- Sol / Luna / Terra are the GPT-5.6 variants (gpt-5.6-sol / -luna / -terra) run through Codex:
  /codex (single task, default worker sol), /codex-fanout (2-3 independent tasks, one worker each, own worktrees), /codex-flow (full loop).
  Wrapper: pwsh -NoProfile -ExecutionPolicy Bypass -File ./.claude/scripts/codex-run.ps1 -Worker <sol|luna|terra> -Effort <low..ultra>.
- ALWAYS review `git diff` + the worker's result before accepting; run tests yourself; you commit. Iterate with codex-run.ps1 -Resume.
- Full rules, brief template and worker traps: skill `codex-orchestration` (.claude/skills/codex-orchestration/).
Guidance, not a hard rule: trivial edits, docs, non-code tasks, and anything the repo's or the user's CLAUDE.md marks as never-delegated are fine to do directly.
'@
exit 0
