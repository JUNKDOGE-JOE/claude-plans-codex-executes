#requires -Version 7
# UserPromptSubmit output is injected into the model context. The hook must consume
# stdin and exit successfully even when project configuration is unavailable.

try { [Console]::In.ReadToEnd() | Out-Null } catch { }

$plannerLabel = 'Claude Code (current session model)'
$executorLabel = 'Codex GPT-5.6 (Sol / Terra / Luna)'
$solModel = 'gpt-5.6-sol'
$terraModel = 'gpt-5.6-terra'
$lunaModel = 'gpt-5.6-luna'
$defaultWorker = 'sol'
$fanoutOrder = 'sol -> terra -> luna'
$plannerModel = $null

try {
    $configPath = if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_PROJECT_DIR)) {
        Join-Path $env:CLAUDE_PROJECT_DIR '.claude/codex-orchestration.json'
    }
    else {
        Join-Path (Split-Path $PSScriptRoot -Parent) 'codex-orchestration.json'
    }
    if (Test-Path -LiteralPath $configPath) {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json
        if (-not $config.planner -or -not $config.executor -or -not $config.executor.workers) { throw 'invalid role config' }
        if (-not [string]::IsNullOrWhiteSpace("$($config.planner.label)")) { $plannerLabel = "$($config.planner.label)" }
        if (-not [string]::IsNullOrWhiteSpace("$($config.executor.label)")) { $executorLabel = "$($config.executor.label)" }
        if (-not [string]::IsNullOrWhiteSpace("$($config.executor.workers.sol)")) { $solModel = "$($config.executor.workers.sol)" }
        if (-not [string]::IsNullOrWhiteSpace("$($config.executor.workers.terra)")) { $terraModel = "$($config.executor.workers.terra)" }
        if (-not [string]::IsNullOrWhiteSpace("$($config.executor.workers.luna)")) { $lunaModel = "$($config.executor.workers.luna)" }
        if (-not [string]::IsNullOrWhiteSpace("$($config.executor.defaultWorker)")) { $defaultWorker = "$($config.executor.defaultWorker)" }
        if (@($config.executor.fanoutOrder).Count -gt 0) { $fanoutOrder = @($config.executor.fanoutOrder) -join ' -> ' }
        if (-not [string]::IsNullOrWhiteSpace("$($config.planner.model)")) { $plannerModel = "$($config.planner.model)" }
    }
}
catch { }

$lines = @(
    "[orchestration reminder] Rule of this repo: $plannerLabel plans -> $executorLabel execute -> $plannerLabel accepts."
    '- You (Claude Code) are PLANNER + ACCEPTOR, not the implementer.'
    "- Workers (Codex CLI slots): sol=$solModel / terra=$terraModel / luna=$lunaModel; default $defaultWorker; fanout order $fanoutOrder."
    '  /codex (single task), /codex-fanout (2-3 independent tasks, one worker each, own worktrees), /codex-flow (full loop).'
    '  Wrapper: pwsh -NoProfile -ExecutionPolicy Bypass -File ./.claude/scripts/codex-run.ps1 -Worker <slot> -Effort <low..ultra>.'
    '- ALWAYS review `git diff` + the worker''s result before accepting; run tests yourself; you commit. Iterate with codex-run.ps1 -Resume.'
    '- Full rules, brief template and worker traps: skill `codex-orchestration` (.claude/skills/codex-orchestration/).'
)
if ($plannerModel) {
    $lines += "- Planner model for this project: $plannerModel (set in .claude/settings.json). If this session runs a different model, tell the user once."
}
$lines += 'Guidance, not a hard rule: trivial edits, docs, non-code tasks, and anything the repo''s or the user''s CLAUDE.md marks as never-delegated are fine to do directly.'

Write-Output ($lines -join "`n")
exit 0
