#requires -Version 7
<#
.SYNOPSIS
  Install, update or remove the codex-orchestration skill for the current user.

.DESCRIPTION
  Copies this skill and its companions into the user's Claude Code and Codex config:

    ~/.claude/skills/codex-orchestration/   the skill itself (this directory)
    ~/.claude/commands/codex*.md            /codex, /codex-fanout, /codex-flow
    ~/.claude/scripts/codex-run.ps1         worker wrapper around `codex exec`
    ~/.claude/hooks/codex-reminder.ps1      UserPromptSubmit reminder, registered in settings.json
    ~/.claude/CLAUDE.md                     policy block, appended only when no policy is present
    ~/.codex/skills/comment-discipline/     worker-side Codex skill that every brief points at

  Re-running updates in place. A target file that differs from what the skill ships is
  backed up as <file>.bak-<stamp> before it is overwritten; settings.json and CLAUDE.md
  are backed up before every write.

.PARAMETER UserHome
  Home directory to install into. Defaults to $env:USERPROFILE (or $HOME). Point it at a
  scratch directory to rehearse the install without touching the real config.
.PARAMETER Uninstall
  Remove everything the installer added. Hand-written CLAUDE.md text is preserved and a
  user-modified file is renamed to .bak-<stamp> instead of being deleted.
.PARAMETER SkipClaudeMd
  Leave ~/.claude/CLAUDE.md alone.
.PARAMETER SkipHook
  Leave the UserPromptSubmit hook entry in settings.json alone.

.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$UserHome = $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }),
    [switch]$Uninstall,
    [switch]$SkipClaudeMd,
    [switch]$SkipHook
)

$ErrorActionPreference = 'Stop'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$skillName = 'codex-orchestration'
$beginMarker = '<!-- codex-orchestration:begin -->'
$endMarker = '<!-- codex-orchestration:end -->'
$commandFiles = @('codex.md', 'codex-fanout.md', 'codex-flow.md')

# This script lives in <skill>/scripts/, so the skill root is one level up.
$src = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $src 'SKILL.md'))) {
    throw "SKILL.md not found at '$src' - run install.ps1 from its place inside the skill's scripts/ directory."
}
$src = (Resolve-Path -LiteralPath $src).Path

if (-not (Test-Path -LiteralPath $UserHome)) { New-Item -ItemType Directory -Force -Path $UserHome | Out-Null }
$UserHome = (Resolve-Path -LiteralPath $UserHome).Path
$claudeDir = Join-Path $UserHome '.claude'
$codexDir = Join-Path $UserHome '.codex'

$dst = [ordered]@{
    Skill      = Join-Path (Join-Path $claudeDir 'skills') $skillName
    Commands   = Join-Path $claudeDir 'commands'
    Wrapper    = Join-Path (Join-Path $claudeDir 'scripts') 'codex-run.ps1'
    Hook       = Join-Path (Join-Path $claudeDir 'hooks') 'codex-reminder.ps1'
    Settings   = Join-Path $claudeDir 'settings.json'
    ClaudeMd   = Join-Path $claudeDir 'CLAUDE.md'
    CodexSkill = Join-Path (Join-Path $codexDir 'skills') 'comment-discipline'
}
# Absolute path on purpose: hook commands are run by a plain shell, so no profile or
# environment expansion can be relied on there.
$hookCommand = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$($dst.Hook)`""

function Write-Step([string]$Message) { Write-Host $Message }

function Test-ReparsePoint([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Get-LinkTarget([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    $t = $item.LinkTarget
    if (-not $t) { $t = @($item.Target)[0] }
    return $t
}

# A junction or symlink is unlinked without touching whatever it points at.
function Remove-DirectorySafely([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (Test-ReparsePoint $Path) { [IO.Directory]::Delete($Path, $false) }
    else { Remove-Item -LiteralPath $Path -Recurse -Force }
}

function Get-Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
}

function Install-File([string]$From, [string]$To) {
    Ensure-Directory (Split-Path -Parent $To)
    if (Test-Path -LiteralPath $To) {
        if ((Get-Hash $From) -eq (Get-Hash $To)) { Write-Step "  = $To (unchanged)"; return }
        Copy-Item -LiteralPath $To -Destination "$To.bak-$stamp"
        Write-Step "  ~ $To (updated; previous copy kept as .bak-$stamp)"
    }
    else { Write-Step "  + $To" }
    Copy-Item -LiteralPath $From -Destination $To -Force
}

# Delete a file this installer put in place; a user-modified copy is renamed, not deleted.
function Remove-File([string]$To, [string]$ShippedCopy) {
    if (-not (Test-Path -LiteralPath $To)) { return }
    if ((Test-Path -LiteralPath $ShippedCopy) -and ((Get-Hash $To) -ne (Get-Hash $ShippedCopy))) {
        Move-Item -LiteralPath $To -Destination "$To.bak-$stamp"
        Write-Step "  ~ $To differs from the shipped copy; kept as .bak-$stamp"
        return
    }
    Remove-Item -LiteralPath $To -Force
    Write-Step "  - $To"
}

function Test-SamePath([string]$A, [string]$B) {
    if (-not (Test-Path -LiteralPath $A) -or -not (Test-Path -LiteralPath $B)) { return $false }
    $seps = [char[]]@([char]92, [char]47)
    return (Resolve-Path -LiteralPath $A).Path.TrimEnd($seps) -ieq (Resolve-Path -LiteralPath $B).Path.TrimEnd($seps)
}

function Install-Directory([string]$From, [string]$To) {
    if (Test-Path -LiteralPath $To) {
        $existing = if (Test-ReparsePoint $To) { Get-LinkTarget $To } else { $To }
        if ($existing -and (Test-SamePath $existing $From)) { Write-Step "  = $To (already is / points at the source)"; return }
        Remove-DirectorySafely $To
    }
    Ensure-Directory (Split-Path -Parent $To)
    Copy-Item -LiteralPath $From -Destination $To -Recurse -Force
    Write-Step "  + $To (mirrored from $From)"
}

# --- settings.json: UserPromptSubmit hook -------------------------------------------------

function Read-Settings {
    if (-not (Test-Path -LiteralPath $dst.Settings)) { return [pscustomobject]@{} }
    $raw = Get-Content -LiteralPath $dst.Settings -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{} }
    return ($raw | ConvertFrom-Json)
}

function Write-Settings($Settings) {
    Ensure-Directory (Split-Path -Parent $dst.Settings)
    if (Test-Path -LiteralPath $dst.Settings) { Copy-Item -LiteralPath $dst.Settings -Destination "$($dst.Settings).bak-$stamp" }
    [IO.File]::WriteAllText($dst.Settings, (ConvertTo-Json -InputObject $Settings -Depth 64) + "`n", $utf8)
}

function Test-OurHook($Entry) {
    foreach ($h in @($Entry.hooks)) { if ("$($h.command)" -like '*codex-reminder.ps1*') { return $true } }
    return $false
}

function Install-Hook {
    $s = Read-Settings
    if (-not $s.PSObject.Properties['hooks'] -or $null -eq $s.hooks) {
        $s | Add-Member -Force -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    }
    if (-not $s.hooks.PSObject.Properties['UserPromptSubmit']) {
        $s.hooks | Add-Member -Force -NotePropertyName UserPromptSubmit -NotePropertyValue @()
    }
    $list = @($s.hooks.UserPromptSubmit)
    if (@($list | Where-Object { Test-OurHook $_ }).Count -gt 0) {
        Write-Step "  = settings.json: UserPromptSubmit hook already registered"
        return
    }
    $entry = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $hookCommand; timeout = 10 }) }
    $s.hooks.UserPromptSubmit = $list + @($entry)
    Write-Settings $s
    Write-Step "  + settings.json: UserPromptSubmit hook registered (backup .bak-$stamp)"
}

function Uninstall-Hook {
    if (-not (Test-Path -LiteralPath $dst.Settings)) { return }
    $s = Read-Settings
    if (-not $s.PSObject.Properties['hooks'] -or $null -eq $s.hooks -or -not $s.hooks.PSObject.Properties['UserPromptSubmit']) { return }
    $list = @($s.hooks.UserPromptSubmit)
    $kept = @($list | Where-Object { -not (Test-OurHook $_) })
    if ($kept.Count -eq $list.Count) { return }
    if ($kept.Count -gt 0) { $s.hooks.UserPromptSubmit = $kept } else { $s.hooks.PSObject.Properties.Remove('UserPromptSubmit') }
    if (@($s.hooks.PSObject.Properties).Count -eq 0) { $s.PSObject.Properties.Remove('hooks') }
    Write-Settings $s
    Write-Step "  - settings.json: UserPromptSubmit hook removed (backup .bak-$stamp)"
}

# --- CLAUDE.md: policy block ---------------------------------------------------------------

function Get-PolicyBlock { (Get-Content -LiteralPath (Join-Path (Join-Path $src 'assets') 'claude-md-block.md') -Raw -Encoding utf8).TrimEnd() }

function Install-ClaudeMd {
    $block = Get-PolicyBlock
    $text = if (Test-Path -LiteralPath $dst.ClaudeMd) { Get-Content -LiteralPath $dst.ClaudeMd -Raw -Encoding utf8 } else { '' }
    if ($null -eq $text) { $text = '' }
    if ($text.Contains("`r`n")) { $block = $block -replace "`n", "`r`n" }
    $pattern = [regex]::Escape($beginMarker) + '[\s\S]*?' + [regex]::Escape($endMarker)
    if ($text -match $pattern) {
        $new = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator] { param($m) $block })
        if ($new -eq $text) { Write-Step "  = CLAUDE.md: policy block up to date"; return }
        Copy-Item -LiteralPath $dst.ClaudeMd -Destination "$($dst.ClaudeMd).bak-$stamp"
        [IO.File]::WriteAllText($dst.ClaudeMd, $new, $utf8)
        Write-Step "  ~ CLAUDE.md: policy block refreshed (backup .bak-$stamp)"
        return
    }
    if ($text -match 'Sol\s*/\s*Luna\s*/\s*Terra') {
        Write-Step "  = CLAUDE.md: already carries a hand-written policy; left untouched"
        Write-Step "    (wrap that section in $beginMarker ... $endMarker to let the installer manage it)"
        return
    }
    Ensure-Directory (Split-Path -Parent $dst.ClaudeMd)
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $sep = if ($text.Length -eq 0 -or $text.EndsWith($nl + $nl)) { '' } elseif ($text.EndsWith($nl)) { $nl } else { $nl + $nl }
    if (Test-Path -LiteralPath $dst.ClaudeMd) { Copy-Item -LiteralPath $dst.ClaudeMd -Destination "$($dst.ClaudeMd).bak-$stamp" }
    [IO.File]::WriteAllText($dst.ClaudeMd, $text + $sep + $block + $nl, $utf8)
    Write-Step "  + CLAUDE.md: policy block appended"
}

function Uninstall-ClaudeMd {
    if (-not (Test-Path -LiteralPath $dst.ClaudeMd)) { return }
    $text = Get-Content -LiteralPath $dst.ClaudeMd -Raw -Encoding utf8
    if ($null -eq $text) { return }
    $pattern = '(\r?\n)*' + [regex]::Escape($beginMarker) + '[\s\S]*?' + [regex]::Escape($endMarker) + '(\r?\n)?'
    if (-not ($text -match $pattern)) { return }
    Copy-Item -LiteralPath $dst.ClaudeMd -Destination "$($dst.ClaudeMd).bak-$stamp"
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $new = [regex]::Replace($text, $pattern, $nl).TrimStart("`r", "`n")
    if ($new.Trim().Length -eq 0) {
        Remove-Item -LiteralPath $dst.ClaudeMd -Force
        Write-Step "  - CLAUDE.md removed (it held only the policy block; backup .bak-$stamp)"
        return
    }
    [IO.File]::WriteAllText($dst.ClaudeMd, $new.TrimEnd() + $nl, $utf8)
    Write-Step "  - CLAUDE.md: policy block removed (backup .bak-$stamp)"
}

# --- main ----------------------------------------------------------------------------------

$mode = if ($Uninstall) { 'uninstall' } else { 'install' }
Write-Step "[$skillName] mode=$mode  source=$src  home=$UserHome"

if ($Uninstall) {
    Write-Step 'Removing files...'
    if (Test-SamePath $src $dst.Skill) { Write-Step "  ! $($dst.Skill) is the source checkout itself; not deleted - remove it by hand if you want it gone" }
    else { Remove-DirectorySafely $dst.Skill; Write-Step "  - $($dst.Skill)" }
    foreach ($f in $commandFiles) { Remove-File (Join-Path $dst.Commands $f) (Join-Path (Join-Path $src 'commands') $f) }
    Remove-File $dst.Wrapper (Join-Path (Join-Path $src 'scripts') 'codex-run.ps1')
    Remove-File $dst.Hook (Join-Path (Join-Path $src 'scripts') 'codex-reminder.ps1')
    Remove-DirectorySafely $dst.CodexSkill; Write-Step "  - $($dst.CodexSkill)"
    if (-not $SkipHook) { Uninstall-Hook }
    if (-not $SkipClaudeMd) { Uninstall-ClaudeMd }
    Write-Step 'Done. Start a new Claude Code session to drop the skill, the commands and the reminder hook.'
    exit 0
}

Write-Step 'Installing files...'
Install-Directory $src $dst.Skill
foreach ($f in $commandFiles) { Install-File (Join-Path (Join-Path $src 'commands') $f) (Join-Path $dst.Commands $f) }
Install-File (Join-Path (Join-Path $src 'scripts') 'codex-run.ps1') $dst.Wrapper
Install-File (Join-Path (Join-Path $src 'scripts') 'codex-reminder.ps1') $dst.Hook
Install-Directory (Join-Path (Join-Path $src 'codex-skills') 'comment-discipline') $dst.CodexSkill
if (-not $SkipHook) { Install-Hook }
if (-not $SkipClaudeMd) { Install-ClaudeMd }

$codexCmd = Get-Command codex -ErrorAction SilentlyContinue
if ($codexCmd) {
    $v = (& codex --version 2>$null | Select-Object -First 1)
    Write-Step "codex CLI found: $v (model ids gpt-5.6-sol / -luna / -terra need codex-cli >= 0.144)"
}
else {
    Write-Step 'WARNING: `codex` is not on PATH. Install the Codex CLI (npm i -g @openai/codex) and run `codex login` before delegating anything.'
}
Write-Step "Done. Start a new Claude Code session: /codex, /codex-fanout, /codex-flow and the '$skillName' skill are now available."
