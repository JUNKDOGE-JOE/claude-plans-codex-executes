#requires -Version 7
<#
.SYNOPSIS
  Install, update or remove the codex-orchestration skill in ONE project (project-level only).

.DESCRIPTION
  Copies this skill and its companions into the target project. Nothing is written outside it:

    <project>/.claude/skills/codex-orchestration/   the skill itself (this directory)
    <project>/.claude/commands/codex*.md            /codex, /codex-fanout, /codex-flow
    <project>/.claude/scripts/codex-run.ps1         worker wrapper around `codex exec`
    <project>/.claude/hooks/codex-reminder.ps1      UserPromptSubmit reminder, registered in
    <project>/.claude/settings.json                   (the command uses $CLAUDE_PROJECT_DIR, so it is portable)
    <project>/CLAUDE.md                             policy block, appended only when no policy is present
    <project>/.agents/skills/comment-discipline/    worker-side Codex skill that every brief points at

  Re-running updates in place. A target file that differs from what the skill ships is backed up
  as <file>.bak-<stamp> before it is overwritten; settings.json and CLAUDE.md are backed up before
  every write. Whether to commit the installed files or keep them local (.git/info/exclude) is the
  project's call.

.PARAMETER Project
  Project root to install into (default: current directory). Normally the git repository root.
.PARAMETER Uninstall
  Remove everything the installer added. Hand-written CLAUDE.md text is preserved and a
  user-modified file is renamed to .bak-<stamp> instead of being deleted.
.PARAMETER SkipClaudeMd
  Leave <project>/CLAUDE.md alone.
.PARAMETER SkipHook
  Leave the UserPromptSubmit hook entry in <project>/.claude/settings.json alone.
.PARAMETER PlannerModel
  Planner model id, or 'current' to follow the active Claude Code session model.
.PARAMETER PlannerLabel
  Display label for the planner role.
.PARAMETER ExecutorModels
  One to three comma-separated Codex model ids assigned to sol, terra and luna.
.PARAMETER ExecutorLabel
  Display label for the executor role.
.PARAMETER CodexCommand
  Codex CLI executable or absolute path used by the worker wrapper.
.PARAMETER Interactive
  Prompt for planner and executor presets. No prompts occur without this switch.

.EXAMPLE
  cd <your-repo>
  pwsh -NoProfile -ExecutionPolicy Bypass -File <clone>\skills\codex-orchestration\scripts\install.ps1 -Project .
.EXAMPLE
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\.claude\skills\codex-orchestration\scripts\install.ps1 -Project . -Uninstall
#>
[CmdletBinding()]
param(
    [string]$Project = (Get-Location).Path,
    [switch]$Uninstall,
    [switch]$SkipClaudeMd,
    [switch]$SkipHook,
    [string]$PlannerModel,
    [string]$PlannerLabel,
    [string]$ExecutorModels,
    [string]$ExecutorLabel,
    [string]$CodexCommand,
    [switch]$Interactive
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

if (-not (Test-Path -LiteralPath $Project)) { throw "Project directory not found: $Project" }
$Project = (Resolve-Path -LiteralPath $Project).Path
$claudeDir = Join-Path $Project '.claude'

$dst = [ordered]@{
    Skill      = Join-Path (Join-Path $claudeDir 'skills') $skillName
    Commands   = Join-Path $claudeDir 'commands'
    Wrapper    = Join-Path (Join-Path $claudeDir 'scripts') 'codex-run.ps1'
    Hook       = Join-Path (Join-Path $claudeDir 'hooks') 'codex-reminder.ps1'
    Settings   = Join-Path $claudeDir 'settings.json'
    Config     = Join-Path $claudeDir 'codex-orchestration.json'
    ClaudeMd   = Join-Path $Project 'CLAUDE.md'
    CodexSkill = Join-Path (Join-Path (Join-Path $Project '.agents') 'skills') 'comment-discipline'
}
# $CLAUDE_PROJECT_DIR is expanded by Claude Code when it runs the hook, so the committed
# settings.json works on every machine that checks the project out.
$hookCommand = 'pwsh -NoProfile -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.claude/hooks/codex-reminder.ps1"'

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

function New-DefaultRoleConfig {
    return [pscustomobject][ordered]@{
        version = 1
        planner = [pscustomobject][ordered]@{
            label = 'Claude Code (current session model)'
            model = $null
        }
        executor = [pscustomobject][ordered]@{
            label = 'Codex GPT-5.6 (Sol / Terra / Luna)'
            codexCommand = 'codex'
            workers = [pscustomobject][ordered]@{
                sol = 'gpt-5.6-sol'
                terra = 'gpt-5.6-terra'
                luna = 'gpt-5.6-luna'
            }
            defaultWorker = 'sol'
            fanoutOrder = @('sol', 'terra', 'luna')
        }
    }
}

function Get-PlannerLabel([AllowNull()][string]$Model) {
    if ([string]::IsNullOrWhiteSpace($Model) -or $Model -eq 'current') { return 'Claude Code (current session model)' }
    switch ($Model) {
        'claude-fable-5' { return 'Claude Fable 5' }
        'claude-opus-5' { return 'Claude Opus 5' }
        'claude-sonnet-5' { return 'Claude Sonnet 5' }
        'claude-haiku-4-5-20251001' { return 'Claude Haiku 4.5' }
        default { return "Claude Code ($Model)" }
    }
}

function ConvertTo-ExecutorModels([string]$Value) {
    $items = @($Value.Split(',', [StringSplitOptions]::None) | ForEach-Object { $_.Trim() })
    if ($items.Count -lt 1 -or $items.Count -gt 3) {
        throw '-ExecutorModels requires 1-3 comma-separated model ids.'
    }
    if (@($items | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw '-ExecutorModels contains an empty item; provide 1-3 non-empty comma-separated model ids.'
    }
    while ($items.Count -lt 3) { $items += $items[-1] }
    return $items
}

function Get-ExecutorLabel([string[]]$Models) {
    if ($Models[0] -ceq 'gpt-5.6-sol' -and $Models[1] -ceq 'gpt-5.6-terra' -and $Models[2] -ceq 'gpt-5.6-luna') {
        return 'Codex GPT-5.6 (Sol / Terra / Luna)'
    }
    if ($Models[0] -ceq $Models[1] -and $Models[1] -ceq $Models[2]) { return "Codex $($Models[0])" }
    return "Codex ($($Models[0]) / $($Models[1]) / $($Models[2]))"
}

function Read-RoleConfig {
    if (-not (Test-Path -LiteralPath $dst.Config)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $dst.Config -Raw -Encoding utf8
        if ([string]::IsNullOrWhiteSpace($raw)) { throw 'file is empty' }
        $config = $raw | ConvertFrom-Json
        if (-not $config.planner -or -not $config.executor -or -not $config.executor.workers) { throw 'required role properties are missing' }
        return $config
    }
    catch {
        throw "Cannot read role config '$($dst.Config)': $($_.Exception.Message)"
    }
}

function Write-RoleConfig($Config) {
    Ensure-Directory (Split-Path -Parent $dst.Config)
    $content = (ConvertTo-Json -InputObject $Config -Depth 10) + "`n"
    if (Test-Path -LiteralPath $dst.Config) {
        $existing = Get-Content -LiteralPath $dst.Config -Raw -Encoding utf8
        if ($existing -ceq $content) { return $false }
        Copy-Item -LiteralPath $dst.Config -Destination "$($dst.Config).bak-$stamp"
        Write-Step "  ~ $($dst.Config) (updated; previous copy kept as .bak-$stamp)"
    }
    else { Write-Step "  + $($dst.Config)" }
    [IO.File]::WriteAllText($dst.Config, $content, $utf8)
    return $true
}

function Read-InteractiveRoles {
    $plannerChoice = Read-Host 'Planner: 1 current session model [default], 2 Claude Fable 5, 3 Claude Opus 5, 4 Claude Sonnet 5, 5 custom id'
    $interactivePlanner = switch ($plannerChoice) {
        { [string]::IsNullOrWhiteSpace($_) -or $_ -eq '1' } { 'current'; break }
        '2' { 'claude-fable-5'; break }
        '3' { 'claude-opus-5'; break }
        '4' { 'claude-sonnet-5'; break }
        '5' { Read-Host 'Planner model id'; break }
        default { throw "Unknown planner menu choice '$plannerChoice'." }
    }
    if ([string]::IsNullOrWhiteSpace($interactivePlanner)) { throw 'Planner model id cannot be empty.' }

    $executorChoice = Read-Host 'Executor: 1 Codex GPT-5.6 Sol/Terra/Luna [default], 2 gpt-5.5 for all slots, 3 gpt-5.4 for all slots, 4 custom comma list'
    $interactiveExecutor = switch ($executorChoice) {
        { [string]::IsNullOrWhiteSpace($_) -or $_ -eq '1' } { 'gpt-5.6-sol,gpt-5.6-terra,gpt-5.6-luna'; break }
        '2' { 'gpt-5.5'; break }
        '3' { 'gpt-5.4'; break }
        '4' { Read-Host 'Executor model ids (1-3, comma-separated)'; break }
        default { throw "Unknown executor menu choice '$executorChoice'." }
    }
    return [pscustomobject]@{ PlannerModel = $interactivePlanner; ExecutorModels = $interactiveExecutor }
}

function Get-NormalizedPath([string]$Path) {
    $seps = [char[]]@([char]92, [char]47)
    return (Resolve-Path -LiteralPath $Path).Path.TrimEnd($seps)
}

function Test-SamePath([string]$A, [string]$B) {
    if (-not (Test-Path -LiteralPath $A) -or -not (Test-Path -LiteralPath $B)) { return $false }
    return (Get-NormalizedPath $A) -ieq (Get-NormalizedPath $B)
}

function Test-PathInside([string]$Child, [string]$Parent) {
    if (-not (Test-Path -LiteralPath $Child) -or -not (Test-Path -LiteralPath $Parent)) { return $false }
    $c = (Get-NormalizedPath $Child) + [IO.Path]::DirectorySeparatorChar
    $p = (Get-NormalizedPath $Parent) + [IO.Path]::DirectorySeparatorChar
    return $c.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)
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

# Remove now-empty parent directories up to (not including) $StopAt.
function Remove-EmptyParents([string]$Path, [string]$StopAt) {
    $dir = Split-Path -Parent $Path
    while ($dir -and (Test-Path -LiteralPath $dir) -and -not (Test-SamePath $dir $StopAt)) {
        if (@(Get-ChildItem -LiteralPath $dir -Force).Count -gt 0) { break }
        Remove-Item -LiteralPath $dir -Force
        $dir = Split-Path -Parent $dir
    }
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

function Install-Settings($Config, [AllowNull()]$PreviousPlannerModel, [bool]$ManageHook) {
    $s = Read-Settings
    $changed = $false
    $hookAdded = $false
    if ($ManageHook) {
        if (-not $s.PSObject.Properties['hooks'] -or $null -eq $s.hooks) {
            $s | Add-Member -Force -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
        }
        if (-not $s.hooks.PSObject.Properties['UserPromptSubmit']) {
            $s.hooks | Add-Member -Force -NotePropertyName UserPromptSubmit -NotePropertyValue @()
        }
        $list = @($s.hooks.UserPromptSubmit)
        if (@($list | Where-Object { Test-OurHook $_ }).Count -eq 0) {
            $entry = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $hookCommand; timeout = 10 }) }
            $s.hooks.UserPromptSubmit = $list + @($entry)
            $changed = $true
            $hookAdded = $true
        }
    }

    $plannerModel = $Config.planner.model
    if (-not [string]::IsNullOrWhiteSpace("$plannerModel")) {
        $canSetModel = -not $s.PSObject.Properties['model'] -or "$($s.model)" -ceq "$plannerModel" -or (
            -not [string]::IsNullOrWhiteSpace("$PreviousPlannerModel") -and "$($s.model)" -ceq "$PreviousPlannerModel"
        )
        if ($canSetModel -and (-not $s.PSObject.Properties['model'] -or "$($s.model)" -cne "$plannerModel")) {
            $s | Add-Member -Force -NotePropertyName model -NotePropertyValue $plannerModel
            $changed = $true
        }
        elseif (-not $canSetModel) {
            Write-Step "  ! settings.json: model '$($s.model)' was not set by this installer; left untouched"
        }
    }
    elseif ($s.PSObject.Properties['model'] -and -not [string]::IsNullOrWhiteSpace("$PreviousPlannerModel") -and "$($s.model)" -ceq "$PreviousPlannerModel") {
        $s.PSObject.Properties.Remove('model')
        $changed = $true
    }

    if ($changed) { Write-Settings $s }
    if ($ManageHook) {
        if ($hookAdded) { Write-Step "  + settings.json: UserPromptSubmit hook registered (backup .bak-$stamp)" }
        else { Write-Step "  = settings.json: UserPromptSubmit hook already registered" }
    }
}

function Uninstall-Settings([AllowNull()]$PlannerModel, [bool]$ManageHook) {
    if (-not (Test-Path -LiteralPath $dst.Settings)) { return }
    $s = Read-Settings
    $changed = $false
    $hookRemoved = $false
    if ($ManageHook -and $s.PSObject.Properties['hooks'] -and $null -ne $s.hooks -and $s.hooks.PSObject.Properties['UserPromptSubmit']) {
        $list = @($s.hooks.UserPromptSubmit)
        $kept = @($list | Where-Object { -not (Test-OurHook $_) })
        if ($kept.Count -ne $list.Count) {
            if ($kept.Count -gt 0) { $s.hooks.UserPromptSubmit = $kept } else { $s.hooks.PSObject.Properties.Remove('UserPromptSubmit') }
            if (@($s.hooks.PSObject.Properties).Count -eq 0) { $s.PSObject.Properties.Remove('hooks') }
            $changed = $true
            $hookRemoved = $true
        }
    }
    if (-not [string]::IsNullOrWhiteSpace("$PlannerModel") -and $s.PSObject.Properties['model'] -and "$($s.model)" -ceq "$PlannerModel") {
        $s.PSObject.Properties.Remove('model')
        $changed = $true
    }
    if ($changed) { Write-Settings $s }
    if ($hookRemoved) { Write-Step "  - settings.json: UserPromptSubmit hook removed (backup .bak-$stamp)" }
}

# --- CLAUDE.md: policy block ---------------------------------------------------------------

function Get-PolicyBlock($Config) {
    $block = (Get-Content -LiteralPath (Join-Path (Join-Path $src 'assets') 'claude-md-block.md') -Raw -Encoding utf8).TrimEnd()
    $workerLines = @($Config.executor.fanoutOrder | ForEach-Object {
        $slot = "$_"
        "  - ``$slot`` → ``$($Config.executor.workers.$slot)``"
    }) -join "`n"
    $fanoutOrder = @($Config.executor.fanoutOrder) -join ' → '
    $plannerNote = if ([string]::IsNullOrWhiteSpace("$($Config.planner.model)")) {
        ''
    }
    else {
        "（项目 ``.claude/settings.json`` 已把默认模型设为 ``$($Config.planner.model)``；会话若在跑别的模型，提醒用户一次。）"
    }
    return $block.Replace('{{PLANNER_LABEL}}', "$($Config.planner.label)").
        Replace('{{EXECUTOR_LABEL}}', "$($Config.executor.label)").
        Replace('{{WORKER_LINES}}', $workerLines).
        Replace('{{DEFAULT_WORKER}}', "$($Config.executor.defaultWorker)").
        Replace('{{FANOUT_ORDER}}', $fanoutOrder).
        Replace('{{PLANNER_MODEL_NOTE}}', $plannerNote)
}

function Install-ClaudeMd($Config) {
    $block = Get-PolicyBlock $Config
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
Write-Step "[$skillName] mode=$mode  source=$src  project=$Project"

# Running from a fresh clone with the clone itself as the project is the classic mistake:
# the skill would be installed into its own source checkout. The installed copy under
# <project>/.claude/skills/ is the one legitimate in-project source (re-run / uninstall).
if ((Test-PathInside $src $Project) -and -not (Test-SamePath $src $dst.Skill)) {
    throw "Refusing to install into '$Project': that is the skill's own source checkout. cd to your project (or pass -Project <repo-root>) and run the installer from the clone."
}
if (-not (Test-Path -LiteralPath (Join-Path $Project '.git'))) {
    Write-Step "  ! $Project has no .git - codex exec needs a git repository (or --skip-git-repo-check); continuing anyway"
}

$existingRoleConfig = Read-RoleConfig
$previousPlannerModel = if ($existingRoleConfig) { $existingRoleConfig.planner.model } else { $null }
$roleConfig = if ($existingRoleConfig) { $existingRoleConfig } else { New-DefaultRoleConfig }

if (-not $Uninstall) {
    if ($Interactive) {
        $interactiveRoles = Read-InteractiveRoles
        if (-not $PSBoundParameters.ContainsKey('PlannerModel')) { $PlannerModel = $interactiveRoles.PlannerModel }
        if (-not $PSBoundParameters.ContainsKey('ExecutorModels')) { $ExecutorModels = $interactiveRoles.ExecutorModels }
    }

    $plannerModelProvided = $PSBoundParameters.ContainsKey('PlannerModel') -or ($Interactive -and -not $PSBoundParameters.ContainsKey('PlannerModel'))
    $executorModelsProvided = $PSBoundParameters.ContainsKey('ExecutorModels') -or ($Interactive -and -not $PSBoundParameters.ContainsKey('ExecutorModels'))
    if ($plannerModelProvided) {
        if ([string]::IsNullOrWhiteSpace($PlannerModel)) { throw '-PlannerModel cannot be empty.' }
        $roleConfig.planner.model = if ($PlannerModel -eq 'current') { $null } else { $PlannerModel }
        if (-not $PSBoundParameters.ContainsKey('PlannerLabel')) { $roleConfig.planner.label = Get-PlannerLabel $PlannerModel }
    }
    if ($PSBoundParameters.ContainsKey('PlannerLabel')) {
        if ([string]::IsNullOrWhiteSpace($PlannerLabel)) { throw '-PlannerLabel cannot be empty.' }
        $roleConfig.planner.label = $PlannerLabel
    }
    if ($executorModelsProvided) {
        $models = ConvertTo-ExecutorModels $ExecutorModels
        $roleConfig.executor.workers.sol = $models[0]
        $roleConfig.executor.workers.terra = $models[1]
        $roleConfig.executor.workers.luna = $models[2]
        if (-not $PSBoundParameters.ContainsKey('ExecutorLabel')) { $roleConfig.executor.label = Get-ExecutorLabel $models }
    }
    if ($PSBoundParameters.ContainsKey('ExecutorLabel')) {
        if ([string]::IsNullOrWhiteSpace($ExecutorLabel)) { throw '-ExecutorLabel cannot be empty.' }
        $roleConfig.executor.label = $ExecutorLabel
    }
    if ($PSBoundParameters.ContainsKey('CodexCommand')) {
        if ([string]::IsNullOrWhiteSpace($CodexCommand)) { throw '-CodexCommand cannot be empty.' }
        $roleConfig.executor.codexCommand = $CodexCommand
    }
}

if ($Uninstall) {
    Write-Step 'Removing files...'
    if (Test-SamePath $src $dst.Skill) { Write-Step "  ! $($dst.Skill) is the installer's own source; not deleted - remove it by hand if you want it gone" }
    else { Remove-DirectorySafely $dst.Skill; Write-Step "  - $($dst.Skill)" }
    foreach ($f in $commandFiles) { Remove-File (Join-Path $dst.Commands $f) (Join-Path (Join-Path $src 'commands') $f) }
    Remove-File $dst.Wrapper (Join-Path (Join-Path $src 'scripts') 'codex-run.ps1')
    Remove-File $dst.Hook (Join-Path (Join-Path $src 'scripts') 'codex-reminder.ps1')
    Remove-DirectorySafely $dst.CodexSkill; Write-Step "  - $($dst.CodexSkill)"
    Remove-EmptyParents $dst.CodexSkill $Project
    Uninstall-Settings $previousPlannerModel (-not $SkipHook)
    if (-not $SkipClaudeMd) { Uninstall-ClaudeMd }
    if (Test-Path -LiteralPath $dst.Config) {
        Remove-Item -LiteralPath $dst.Config -Force
        Write-Step "  - $($dst.Config)"
    }
    Write-Step 'Done. Start a new Claude Code session in the project to drop the skill, the commands and the reminder hook.'
    exit 0
}

Write-Step 'Installing files...'
if (-not $existingRoleConfig -or $plannerModelProvided -or $executorModelsProvided -or $PSBoundParameters.ContainsKey('PlannerLabel') -or $PSBoundParameters.ContainsKey('ExecutorLabel') -or $PSBoundParameters.ContainsKey('CodexCommand')) {
    Write-RoleConfig $roleConfig | Out-Null
}
Install-Directory $src $dst.Skill
foreach ($f in $commandFiles) { Install-File (Join-Path (Join-Path $src 'commands') $f) (Join-Path $dst.Commands $f) }
Install-File (Join-Path (Join-Path $src 'scripts') 'codex-run.ps1') $dst.Wrapper
Install-File (Join-Path (Join-Path $src 'scripts') 'codex-reminder.ps1') $dst.Hook
Install-Directory (Join-Path (Join-Path $src 'codex-skills') 'comment-discipline') $dst.CodexSkill
Install-Settings $roleConfig $previousPlannerModel (-not $SkipHook)
if (-not $SkipClaudeMd) { Install-ClaudeMd $roleConfig }

$configuredCodexCommand = "$($roleConfig.executor.codexCommand)"
$codexCmd = Get-Command $configuredCodexCommand -ErrorAction SilentlyContinue
if ($codexCmd) {
    $v = (& $configuredCodexCommand --version 2>$null | Select-Object -First 1)
    Write-Step "codex CLI found: $v (model ids gpt-5.6-sol / -luna / -terra need codex-cli >= 0.144)"
}
else {
    Write-Step "WARNING: '$configuredCodexCommand' is not available. Install the Codex CLI (npm i -g @openai/codex), run 'codex login', or update -CodexCommand before delegating anything."
}
Write-Step "Done. Start a new Claude Code session in $Project - /codex, /codex-fanout, /codex-flow and the '$skillName' skill are available there."
Write-Step "Decide whether to commit .claude/, CLAUDE.md and .agents/ or keep them local via .git/info/exclude."
Write-Step "Roles: planner=$($roleConfig.planner.label); executor=$($roleConfig.executor.label) [sol=$($roleConfig.executor.workers.sol) terra=$($roleConfig.executor.workers.terra) luna=$($roleConfig.executor.workers.luna)]  (change with -PlannerModel / -ExecutorModels or -Interactive)"
