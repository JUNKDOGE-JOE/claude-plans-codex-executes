#requires -Version 7
# UserPromptSubmit hook (user scope, ~/.claude) - keeps Claude/Fable anchored to the
# orchestration workflow across long sessions and context compaction. Stdout from this
# hook is injected into the model's context for the turn. Gentle nudge, not a hard
# block; always exits 0.
#
# Installed by the codex-orchestration skill (scripts/install.ps1). If the current
# project ships its own copy of this hook, stay silent so the reminder is not injected
# twice (hooks from every settings scope run).

$payload = ''
try { $payload = [Console]::In.ReadToEnd() } catch { }

$projectDir = $env:CLAUDE_PROJECT_DIR
if (-not $projectDir -and $payload) {
    try { $projectDir = (ConvertFrom-Json $payload).cwd } catch { }
}
if ($projectDir) {
    $projectHook = Join-Path $projectDir '.claude\hooks\codex-reminder.ps1'
    if (Test-Path -LiteralPath $projectHook) { exit 0 }
}

Write-Output @'
[orchestration reminder] Rule on this machine: Fable plans -> Sol / Luna / Terra execute -> Fable accepts.
- You (Fable 5) are PLANNER + ACCEPTOR, not the implementer.
- Sol / Luna / Terra are the GPT-5.6 variants (gpt-5.6-sol / -luna / -terra) run through Codex:
  /codex (single task, default worker sol), /codex-fanout (2-3 independent tasks, one worker each, own worktrees), /codex-flow (full loop).
  Wrapper: pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\codex-run.ps1" -Worker <sol|luna|terra> -Effort <low..ultra>.
- ALWAYS review `git diff` + the worker's result before accepting; run tests yourself; you commit. Iterate with codex-run.ps1 -Resume.
- EXCEPTION (all-Fable, never delegated): shader authoring - DynamicFX @dynamicfx shaders, GLSL, Shadertoy ports, examples/*.glsl, shader compile/visual debugging and the live-AE (ae-mcp /exec) iteration loop.
- Full rules, brief template and worker traps: skill `codex-orchestration` (~/.claude/skills/codex-orchestration/).
Guidance, not a hard rule: trivial edits, docs, and non-code tasks are fine to do directly.
'@
exit 0
