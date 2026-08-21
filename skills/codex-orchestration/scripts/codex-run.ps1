#requires -Version 7
<#
.SYNOPSIS
  Delegate an implementation task to Codex CLI (headless) and capture its result.

.DESCRIPTION
  Thin, robust wrapper around `codex exec`. The task brief is passed via STDIN
  (avoids PowerShell quoting problems and supports multi-line / non-ASCII briefs).
  Codex's final message is written to a result file and echoed back.

  Default posture: `--sandbox workspace-write` - Codex may edit files inside the
  workspace, run commands, and use the network. In `exec` (non-interactive) mode
  the approval policy defaults to `never`, so it never blocks; it cannot write
  outside the workspace. Use -Bypass for full access, or -AddDir to grant extra
  writable directories.

  Worker slots, model ids, role labels and the Codex executable are resolved from
  .claude/codex-orchestration.json. Built-in defaults preserve the Sol / Terra /
  Luna mapping when no readable config is present. -Model overrides the mapping.
  Effort: low|medium|high|xhigh|max|ultra ('ultra' is accepted by Sol/Terra only;
  Luna caps at 'max'). Verified on codex-cli 0.144.1 (2026-08-19).

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File ./.claude/scripts/codex-run.ps1 `
    -BriefFile .codex/brief.md -Worker sol -Effort medium

.EXAMPLE
  # Iterate on the most recent Codex session with review feedback (same context):
  pwsh -NoProfile -ExecutionPolicy Bypass -File ./.claude/scripts/codex-run.ps1 `
    -Resume -Brief "Fix the failing test in tests/test_x.py: ..." -Worker sol
#>
[CmdletBinding()]
param(
    [string]$Brief,
    [string]$BriefFile,
    [string]$Worker = '',
    [string]$Model = '',
    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max', 'ultra')]
    [string]$Effort = 'medium',
    [string]$Cwd = (Get-Location).Path,
    [string]$ResultFile,
    [switch]$Resume,
    [string]$SessionId,
    [string[]]$AddDir,
    [switch]$Bypass,
    # Optional service-tier override (e.g. 'fast' or 'flex'); empty = use config.
    # CLI >= ~0.138 accepts the config's "priority" natively, so usually unneeded.
    [string]$ServiceTier = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$Cwd = (Resolve-Path -LiteralPath $Cwd).Path
$defaultConfig = [pscustomobject]@{
    planner = [pscustomobject]@{ label = 'Claude Code (current session model)'; model = $null }
    executor = [pscustomobject]@{
        label = 'Codex GPT-5.6 (Sol / Terra / Luna)'
        codexCommand = 'codex'
        workers = [pscustomobject][ordered]@{ sol = 'gpt-5.6-sol'; terra = 'gpt-5.6-terra'; luna = 'gpt-5.6-luna' }
        defaultWorker = 'sol'
        fanoutOrder = @('sol', 'terra', 'luna')
    }
}
$config = $defaultConfig
$configSource = 'built-in defaults'
$scriptConfig = Join-Path (Split-Path $PSScriptRoot -Parent) 'codex-orchestration.json'
$cwdConfig = Join-Path $Cwd '.claude/codex-orchestration.json'
$configPath = $null
$candidatePath = $null
try {
    foreach ($candidatePath in @($scriptConfig, $cwdConfig)) {
        if (Test-Path -LiteralPath $candidatePath) { $configPath = $candidatePath; break }
    }
    if ($configPath) {
        $candidate = Get-Content -LiteralPath $configPath -Raw -Encoding utf8 | ConvertFrom-Json
        if (-not $candidate.planner -or -not $candidate.executor -or -not $candidate.executor.workers) { throw 'required role properties are missing' }
        $config = $candidate
        $configSource = $configPath
    }
}
catch {
    $failedPath = if ($configPath) { $configPath } else { $candidatePath }
    Write-Warning "Cannot read role config '$failedPath': $($_.Exception.Message); using built-in defaults."
}

if ([string]::IsNullOrWhiteSpace($Worker)) {
    $Worker = if ([string]::IsNullOrWhiteSpace("$($config.executor.defaultWorker)")) { 'sol' } else { "$($config.executor.defaultWorker)" }
}
if ([string]::IsNullOrWhiteSpace($Model)) {
    $workerProperty = $config.executor.workers.PSObject.Properties[$Worker]
    if (-not $workerProperty) {
        $configuredWorkers = @($config.executor.workers.PSObject.Properties.Name) -join ', '
        throw "Unknown worker '$Worker'. Configured workers: $configuredWorkers ($configSource)"
    }
    $Model = "$($workerProperty.Value)"
}
if ($Effort -eq 'ultra' -and $Model.EndsWith('-luna', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Luna caps at -Effort max ('ultra' is Sol/Terra only)."
}
$plannerLabel = if ([string]::IsNullOrWhiteSpace("$($config.planner.label)")) { $defaultConfig.planner.label } else { "$($config.planner.label)" }
$executorLabel = if ([string]::IsNullOrWhiteSpace("$($config.executor.label)")) { $defaultConfig.executor.label } else { "$($config.executor.label)" }
$codexCommand = if ([string]::IsNullOrWhiteSpace("$($config.executor.codexCommand)")) { 'codex' } else { "$($config.executor.codexCommand)" }
$codexExecutable = Get-Command $codexCommand -ErrorAction SilentlyContinue
if (-not $codexExecutable) {
    $commandConfigPath = if ($configSource -eq 'built-in defaults') { $cwdConfig } else { $configSource }
    $missingMessage = "Codex CLI '$codexCommand' not found - install it (npm i -g @openai/codex) or set executor.codexCommand in $commandConfigPath"
    if ($DryRun) { Write-Warning $missingMessage } else { throw $missingMessage }
}

# UTF-8 on the pipe so non-ASCII (e.g. Chinese) briefs reach Codex intact.
$utf8 = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = $utf8
try { [Console]::OutputEncoding = $utf8 } catch { }

# Scratch dir inside the workspace (gitignored) for briefs + results.
$scratch = Join-Path $Cwd '.codex'
if (-not (Test-Path $scratch)) { New-Item -ItemType Directory -Force -Path $scratch | Out-Null }
$gi = Join-Path $scratch '.gitignore'
if (-not (Test-Path $gi)) { Set-Content -LiteralPath $gi -Value '*' -Encoding utf8 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# Resolve the brief into a file we can stream from stdin.
if ($BriefFile) {
    if (-not (Test-Path $BriefFile)) { throw "Brief file not found: $BriefFile" }
    $briefPath = (Resolve-Path -LiteralPath $BriefFile).Path
}
elseif (-not [string]::IsNullOrWhiteSpace($Brief)) {
    $briefPath = Join-Path $scratch "brief-$stamp.md"
    Set-Content -LiteralPath $briefPath -Value $Brief -Encoding utf8
}
elseif ($DryRun) {
    # A dry run only previews the resolved call, so the brief may be omitted.
    $briefPath = '<none: dry run>'
}
else {
    throw "Provide -BriefFile <path> or -Brief '<text>'."
}

if (-not $ResultFile) { $ResultFile = Join-Path $scratch "result-$stamp.md" }

# Sandbox / approval flags.
if ($Bypass) {
    $sandbox = @('--dangerously-bypass-approvals-and-sandbox')
}
elseif ($Resume) {
    # `exec resume` does not accept -s/-a; --full-auto is its non-bypass option.
    $sandbox = @('--full-auto')
}
else {
    # `codex exec` has no -a/--ask-for-approval (that lives on the top-level CLI);
    # exec defaults the approval policy to `never`, so workspace-write is enough.
    $sandbox = @('--sandbox', 'workspace-write')
}

# Config overrides.
$cfg = @('-c', "model_reasoning_effort=$Effort")
if ($ServiceTier) { $cfg += @('-c', "service_tier=$ServiceTier") }

# Extra writable dirs.
$addDirArgs = @()
foreach ($d in $AddDir) { $addDirArgs += @('--add-dir', $d) }

# Build the codex argument list.
if ($Resume) {
    $codexArgs = @('exec', 'resume')
    if ($SessionId) { $codexArgs += $SessionId } else { $codexArgs += '--last' }
    $codexArgs += $sandbox + @('-m', $Model) + $cfg + @('-o', $ResultFile, '-')
}
else {
    $codexArgs = @('exec') + $sandbox + @('-m', $Model, '-C', $Cwd) + $cfg + @('-o', $ResultFile) + $addDirArgs + @('-')
}

Write-Host "[codex-run] worker=$Worker model=$Model effort=$Effort cwd=$Cwd resume=$($Resume.IsPresent) bypass=$($Bypass.IsPresent)"
Write-Host "[codex-run] roles: planner=$plannerLabel executor=$executorLabel (config: $configSource)"
Write-Host "[codex-run] brief=$briefPath"
Write-Host "[codex-run] result=$ResultFile"

if ($DryRun) {
    Write-Host "[codex-run] dry-run: $codexCommand $($codexArgs -join ' ')"
    exit 0
}

# `resume` has no -C; it filters sessions by cwd, so run from $Cwd.
$pushed = $false
if ($Resume) { Push-Location -LiteralPath $Cwd; $pushed = $true }
try {
    Get-Content -LiteralPath $briefPath -Raw | & $codexCommand @codexArgs
    $code = $LASTEXITCODE
}
finally {
    if ($pushed) { Pop-Location }
}

Write-Host ''
Write-Host "=== CODEX EXIT $code ==="
if (Test-Path $ResultFile) {
    Write-Host "=== CODEX RESULT ($ResultFile) ==="
    Get-Content -LiteralPath $ResultFile -Raw
}
else {
    Write-Host '!! No result file written (Codex likely failed before finishing).'
}
exit $code
