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

  Driven by Claude Code (Fable) as orchestrator: Fable writes a brief, runs this
  script, then reviews `git diff` + the result before accepting.

  Workers (rule of this repo: Fable plans -> Sol / Luna / Terra execute -> Fable
  accepts): -Worker sol|luna|terra selects the GPT-5.6 variant gpt-5.6-<worker>.
  Default worker is sol. -Model overrides -Worker when both are given.
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
    # Worker name -> GPT-5.6 variant. Ignored when -Model is given explicitly.
    [ValidateSet('sol', 'luna', 'terra')]
    [string]$Worker = 'sol',
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
    [string]$ServiceTier = ''
)

$ErrorActionPreference = 'Stop'

# Resolve the worker name into a concrete model id unless -Model was given.
if ([string]::IsNullOrWhiteSpace($Model)) { $Model = "gpt-5.6-$Worker" }
if ($Effort -eq 'ultra' -and $Model -eq 'gpt-5.6-luna') {
    throw "Luna caps at -Effort max ('ultra' is Sol/Terra only)."
}

# UTF-8 on the pipe so non-ASCII (e.g. Chinese) briefs reach Codex intact.
$utf8 = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = $utf8
try { [Console]::OutputEncoding = $utf8 } catch { }

$Cwd = (Resolve-Path -LiteralPath $Cwd).Path

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
Write-Host "[codex-run] brief=$briefPath"
Write-Host "[codex-run] result=$ResultFile"

# `resume` has no -C; it filters sessions by cwd, so run from $Cwd.
$pushed = $false
if ($Resume) { Push-Location -LiteralPath $Cwd; $pushed = $true }
try {
    Get-Content -LiteralPath $briefPath -Raw | & codex @codexArgs
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
