$ErrorActionPreference = 'Stop'
$clone = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$inst = Join-Path $clone 'skills/codex-orchestration/scripts/install.ps1'
$t = Join-Path ([IO.Path]::GetTempPath()) 'codex-orchestration-tests'
if (Test-Path $t) { Remove-Item $t -Recurse -Force }
New-Item -ItemType Directory -Force $t | Out-Null
$script:fails = 0
function Run($a, [switch]$ExpectFail) {
    $ErrorActionPreference = 'Continue'
    $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File $inst @a 2>&1 | ForEach-Object { "    $_" }
    $code = $LASTEXITCODE
    if ($ExpectFail) { if ($code -eq 0) { "    (expected failure but exit 0)"; $script:fails++ } else { "    (failed as expected, exit $code)" } }
    elseif ($code -ne 0) { "    (exit $code)"; $script:fails++ }
    $out
}
function Assert($cond, $msg) { if ($cond) { "  PASS $msg" } else { "  FAIL $msg"; $script:fails++ } }
function ReadJson($p) { Get-Content -LiteralPath $p -Raw | ConvertFrom-Json }
function NewProj($name) { $p = Join-Path $t $name; New-Item -ItemType Directory -Force $p | Out-Null; git -C $p init -q; return $p }
function Invoke-PwshFile([string]$Path, [string[]]$Arguments, [AllowNull()][string]$InputText = $null) {
    $ErrorActionPreference = 'Continue'
    if ($null -eq $InputText) { $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1 }
    else { $output = $InputText | & pwsh -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1 }
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    return [pscustomobject]@{ Code = $code; Output = @($output | ForEach-Object { "$_" }) }
}

"== T1 fresh project: install =="
$p1 = NewProj 'proj1'
Run @('-Project', $p1)
Assert (Test-Path (Join-Path $p1 '.claude/skills/codex-orchestration/SKILL.md')) 'skill copied'
Assert (Test-Path (Join-Path $p1 '.claude/skills/codex-orchestration/references/worker-traps.md')) 'skill references copied'
Assert (Test-Path (Join-Path $p1 '.claude/commands/codex-fanout.md')) 'commands copied'
Assert (Test-Path (Join-Path $p1 '.claude/scripts/codex-run.ps1')) 'wrapper copied'
Assert (Test-Path (Join-Path $p1 '.claude/hooks/codex-reminder.ps1')) 'hook copied'
Assert (Test-Path (Join-Path $p1 '.claude/codex-orchestration.json')) 'default role config written'
$roles1 = ReadJson (Join-Path $p1 '.claude/codex-orchestration.json')
Assert ($roles1.version -eq 1 -and $null -eq $roles1.planner.model -and $roles1.executor.workers.sol -eq 'gpt-5.6-sol' -and $roles1.executor.workers.terra -eq 'gpt-5.6-terra' -and $roles1.executor.workers.luna -eq 'gpt-5.6-luna') 'default role config content'
Assert (Test-Path (Join-Path $p1 '.agents/skills/comment-discipline/agents/openai.yaml')) 'codex skill copied to .agents/skills'
Assert (-not (Test-Path (Join-Path $p1 '.codex'))) 'installer does not create .codex (wrapper scratch only)'
$s = ReadJson (Join-Path $p1 '.claude/settings.json')
Assert (@($s.hooks.UserPromptSubmit).Count -eq 1) 'one UserPromptSubmit entry'
$cmd = $s.hooks.UserPromptSubmit[0].hooks[0].command
Assert ($cmd -like '*$CLAUDE_PROJECT_DIR/.claude/hooks/codex-reminder.ps1*') "hook command is portable: $cmd"
Assert ($s.hooks.UserPromptSubmit[0].hooks[0].timeout -eq 10) 'hook timeout 10'
$c = Get-Content (Join-Path $p1 'CLAUDE.md') -Raw
Assert ($c.Contains('<!-- codex-orchestration:begin -->') -and $c.Contains('<!-- codex-orchestration:end -->')) 'CLAUDE.md block appended at project root'

"== T1b re-run: idempotent =="
$out = Run @('-Project', $p1)
$out
Assert (($out -join "`n") -notmatch '\.bak-') 'no backups created on identical re-run'
$s = ReadJson (Join-Path $p1 '.claude/settings.json')
Assert (@($s.hooks.UserPromptSubmit).Count -eq 1) 'still one hook entry'
$c2 = Get-Content (Join-Path $p1 'CLAUDE.md') -Raw
Assert ($c2 -eq $c) 'CLAUDE.md unchanged'
Assert (([regex]::Matches($c2, 'codex-orchestration:begin')).Count -eq 1) 'block not duplicated'

"== T1c re-run FROM the installed copy (legit in-project source) =="
$instInner = Join-Path $p1 '.claude/skills/codex-orchestration/scripts/install.ps1'
$ErrorActionPreference = 'Continue'
$out2 = & pwsh -NoProfile -ExecutionPolicy Bypass -File $instInner -Project $p1 2>&1 | ForEach-Object { "    $_" }
$code2 = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$out2
Assert ($code2 -eq 0) 'installed copy can re-run against its own project'
Assert (($out2 -join "`n") -match 'already is / points at the source') 'skill dir recognised as the source, not re-copied'

"== T1d uninstall =="
Run @('-Project', $p1, '-Uninstall')
Assert (-not (Test-Path (Join-Path $p1 '.claude/skills/codex-orchestration'))) 'skill removed'
Assert (-not (Test-Path (Join-Path $p1 '.claude/commands/codex.md'))) 'commands removed'
Assert (-not (Test-Path (Join-Path $p1 '.claude/scripts/codex-run.ps1'))) 'wrapper removed'
Assert (-not (Test-Path (Join-Path $p1 '.claude/hooks/codex-reminder.ps1'))) 'hook removed'
Assert (-not (Test-Path (Join-Path $p1 '.claude/codex-orchestration.json'))) 'role config removed'
Assert (-not (Test-Path (Join-Path $p1 '.agents'))) '.agents removed entirely when it held only our skill'
Assert (-not (Test-Path (Join-Path $p1 'CLAUDE.md'))) 'CLAUDE.md (block-only) removed'
$s = ReadJson (Join-Path $p1 '.claude/settings.json')
Assert (-not $s.PSObject.Properties['hooks']) 'hooks property removed when empty'

"== T2 existing project: other hooks + hand-written policy (CRLF) + another .agents skill =="
$p2 = NewProj 'proj2'
New-Item -ItemType Directory -Force (Join-Path $p2 '.claude') | Out-Null
New-Item -ItemType Directory -Force (Join-Path $p2 '.agents/skills/other-skill') | Out-Null
Set-Content (Join-Path $p2 '.agents/skills/other-skill/SKILL.md') 'other'
$settings = [ordered]@{ permissions = [ordered]@{ allow = @('Bash(npm test)') }; hooks = [ordered]@{ UserPromptSubmit = @(@{ hooks = @(@{ type = 'command'; command = 'echo other' }) }); PreToolUse = @(@{ matcher = 'Bash'; hooks = @(@{ type = 'command'; command = 'echo pre' }) }) } }
[IO.File]::WriteAllText((Join-Path $p2 '.claude/settings.json'), (ConvertTo-Json -InputObject $settings -Depth 10))
$hand = "# CLAUDE.md`r`n`r`n## rules`r`n`r`nClaude plans -> Sol / Luna / Terra execute.`r`n"
[IO.File]::WriteAllText((Join-Path $p2 'CLAUDE.md'), $hand)
Run @('-Project', $p2)
$s = ReadJson (Join-Path $p2 '.claude/settings.json')
Assert (@($s.permissions.allow).Count -eq 1) 'unrelated setting preserved'
Assert (@($s.hooks.UserPromptSubmit).Count -eq 2) 'our hook appended after existing one'
Assert ($s.hooks.UserPromptSubmit[0].hooks[0].command -eq 'echo other') 'existing hook kept first'
Assert (@($s.hooks.PreToolUse).Count -eq 1 -and $s.hooks.PreToolUse[0].matcher -eq 'Bash') 'PreToolUse preserved'
Assert ((Get-Content (Join-Path $p2 'CLAUDE.md') -Raw) -eq $hand) 'hand-written CLAUDE.md untouched'
Assert ((Get-ChildItem (Join-Path $p2 '.claude') -Filter 'settings.json.bak-*').Count -eq 1) 'settings backup written'
Assert (Test-Path (Join-Path $p2 '.agents/skills/other-skill/SKILL.md')) 'other .agents skill untouched by install'

"== T2b modify a command, then uninstall keeps it as .bak and leaves the other skill =="
Add-Content (Join-Path $p2 '.claude/commands/codex.md') 'user edit'
Run @('-Project', $p2, '-Uninstall')
Assert ((Get-ChildItem (Join-Path $p2 '.claude/commands') -Filter 'codex.md.bak-*').Count -eq 1) 'modified command preserved as .bak'
Assert (-not (Test-Path (Join-Path $p2 '.claude/commands/codex.md'))) 'modified command moved away'
Assert (-not (Test-Path (Join-Path $p2 '.claude/commands/codex-flow.md'))) 'unmodified command removed'
$s = ReadJson (Join-Path $p2 '.claude/settings.json')
Assert (@($s.hooks.UserPromptSubmit).Count -eq 1 -and $s.hooks.UserPromptSubmit[0].hooks[0].command -eq 'echo other') 'only our hook removed'
Assert (@($s.hooks.PreToolUse).Count -eq 1) 'PreToolUse still there'
Assert ((Get-Content (Join-Path $p2 'CLAUDE.md') -Raw) -eq $hand) 'hand-written CLAUDE.md still untouched after uninstall'
Assert ((Test-Path (Join-Path $p2 '.agents/skills/other-skill/SKILL.md')) -and -not (Test-Path (Join-Path $p2 '.agents/skills/comment-discipline'))) 'only our .agents skill removed, other kept'

"== T3 stale managed block gets refreshed; -SkipHook =="
$p3 = NewProj 'proj3'
[IO.File]::WriteAllText((Join-Path $p3 'CLAUDE.md'), "# mine`n`n<!-- codex-orchestration:begin -->`nold stuff`n<!-- codex-orchestration:end -->`n`n# after`n")
Run @('-Project', $p3, '-SkipHook')
$c3 = Get-Content (Join-Path $p3 'CLAUDE.md') -Raw
Assert (-not $c3.Contains('old stuff')) 'stale block replaced'
Assert ($c3.StartsWith("# mine`n") -and $c3.Contains("`n# after`n")) 'surrounding text preserved'
Assert ($c3.Contains('规划')) 'new block present'
Assert (-not (Test-Path (Join-Path $p3 '.claude/settings.json'))) '-SkipHook wrote no settings.json'
Run @('-Project', $p3, '-Uninstall', '-SkipHook')
$c3b = Get-Content (Join-Path $p3 'CLAUDE.md') -Raw
Assert ($c3b -eq "# mine`n`n# after`n") "block removed cleanly (got: $($c3b -replace "`n", '|'))"

"== T4 skill dir is a junction to the source =="
$p4 = NewProj 'proj4'
New-Item -ItemType Directory -Force (Join-Path $p4 '.claude/skills') | Out-Null
$srcSkill = (Resolve-Path (Join-Path $clone 'skills/codex-orchestration')).Path
New-Item -ItemType Junction -Path (Join-Path $p4 '.claude/skills/codex-orchestration') -Target $srcSkill | Out-Null
Run @('-Project', $p4, '-SkipHook', '-SkipClaudeMd')
Assert (Test-Path (Join-Path $srcSkill 'SKILL.md')) 'source still intact after install through junction'
Assert ((Get-Item (Join-Path $p4 '.claude/skills/codex-orchestration') -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) 'junction kept, not replaced by a copy'
Run @('-Project', $p4, '-Uninstall', '-SkipHook', '-SkipClaudeMd')
Assert (-not (Test-Path (Join-Path $p4 '.claude/skills/codex-orchestration'))) 'junction unlinked on uninstall'
Assert (Test-Path (Join-Path $srcSkill 'SKILL.md')) 'source survives uninstall (junction target untouched)'

"== T5 guard: refuse to install into the skill's own clone =="
$cloneAgentsBefore = Test-Path (Join-Path $clone '.agents')
Run @('-Project', $clone) -ExpectFail
Assert (-not (Test-Path (Join-Path $clone '.claude'))) 'no .claude created in the clone'
Assert (-not (Test-Path (Join-Path $clone 'CLAUDE.md'))) 'no CLAUDE.md created in the clone'
Assert ((Test-Path (Join-Path $clone '.agents')) -eq $cloneAgentsBefore) 'no .agents created in the clone'

"== T6 non-git directory: warns but proceeds =="
$p6 = Join-Path $t 'proj6'; New-Item -ItemType Directory -Force $p6 | Out-Null
$out6 = Run @('-Project', $p6, '-SkipHook', '-SkipClaudeMd')
$out6
Assert (($out6 -join "`n") -match 'has no \.git') 'warned about missing .git'
Assert (Test-Path (Join-Path $p6 '.claude/commands/codex.md')) 'still installed'

"== T7 missing project dir: hard error =="
Run @('-Project', (Join-Path $t 'does-not-exist')) -ExpectFail

"== T8 custom roles =="
$p8 = NewProj 'proj8'
Run @('-Project', $p8, '-PlannerModel', 'claude-opus-5', '-ExecutorModels', 'gpt-5.5,gpt-5.4')
$roles8 = ReadJson (Join-Path $p8 '.claude/codex-orchestration.json')
Assert ($roles8.executor.workers.sol -eq 'gpt-5.5' -and $roles8.executor.workers.terra -eq 'gpt-5.4' -and $roles8.executor.workers.luna -eq 'gpt-5.4') 'custom executor models repeat the last id'
Assert ($roles8.planner.label -eq 'Claude Opus 5') 'planner auto label'
Assert ($roles8.executor.label -eq 'Codex (gpt-5.5 / gpt-5.4 / gpt-5.4)') 'executor auto label'
$settings8 = ReadJson (Join-Path $p8 '.claude/settings.json')
Assert ($settings8.model -eq 'claude-opus-5') 'planner model written to settings'
Assert (@($settings8.hooks.UserPromptSubmit).Count -eq 1 -and "$($settings8.hooks.UserPromptSubmit[0].hooks[0].command)" -like '*codex-reminder.ps1*') 'planner setting and hook coexist'
$claude8 = Get-Content -LiteralPath (Join-Path $p8 'CLAUDE.md') -Raw
Assert ($claude8.Contains('Claude Opus 5') -and $claude8.Contains('Codex (gpt-5.5 / gpt-5.4 / gpt-5.4)')) 'custom role labels rendered'
Assert ($claude8.Contains('  - `sol` → `gpt-5.5`') -and $claude8.Contains('  - `terra` → `gpt-5.4`') -and $claude8.Contains('  - `luna` → `gpt-5.4`')) 'three worker lines rendered'
Assert ($claude8.Contains('`.claude/settings.json` 已把默认模型设为 `claude-opus-5`')) 'planner settings note rendered'

"== T9 role config re-run and partial merge =="
$config8Path = Join-Path $p8 '.claude/codex-orchestration.json'
$config8Before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($config8Path))
Run @('-Project', $p8)
$config8After = [Convert]::ToBase64String([IO.File]::ReadAllBytes($config8Path))
Assert ($config8After -ceq $config8Before) 're-run without role parameters keeps config byte-identical'
Assert ((Get-ChildItem (Join-Path $p8 '.claude') -Filter 'codex-orchestration.json.bak-*').Count -eq 0) 'unchanged config creates no backup'
Run @('-Project', $p8, '-ExecutorModels', 'gpt-5.6-sol,gpt-5.6-terra,gpt-5.6-luna')
$roles9 = ReadJson $config8Path
Assert ($roles9.planner.model -eq 'claude-opus-5' -and $roles9.planner.label -eq 'Claude Opus 5') 'executor-only update preserves planner'
Assert ($roles9.executor.workers.sol -eq 'gpt-5.6-sol' -and $roles9.executor.workers.terra -eq 'gpt-5.6-terra' -and $roles9.executor.workers.luna -eq 'gpt-5.6-luna') 'executor-only update changes all worker models'
Assert ((Get-ChildItem (Join-Path $p8 '.claude') -Filter 'codex-orchestration.json.bak-*').Count -eq 1) 'changed config creates one backup'

"== T10 current planner cleanup and uninstall =="
$settings10 = ReadJson (Join-Path $p8 '.claude/settings.json')
$settings10 | Add-Member -Force -NotePropertyName keepMe -NotePropertyValue 'yes'
[IO.File]::WriteAllText((Join-Path $p8 '.claude/settings.json'), (ConvertTo-Json -InputObject $settings10 -Depth 10) + "`n", [Text.UTF8Encoding]::new($false))
Run @('-Project', $p8, '-PlannerModel', 'current')
$settings10b = ReadJson (Join-Path $p8 '.claude/settings.json')
Assert (-not $settings10b.PSObject.Properties['model']) 'current planner removes installer-owned model setting'
Assert ($settings10b.keepMe -eq 'yes' -and @($settings10b.hooks.UserPromptSubmit).Count -eq 1) 'current planner leaves other settings and hook'
Run @('-Project', $p8, '-Uninstall')
Assert (-not (Test-Path $config8Path)) 'uninstall deletes role config'
Assert ((Get-ChildItem (Join-Path $p8 '.claude') -Filter 'codex-orchestration.json.bak-*').Count -ge 1) 'uninstall leaves config backups'

"== T11 installed wrapper dry runs =="
$p11 = NewProj 'proj11'
Run @('-Project', $p11, '-PlannerModel', 'claude-opus-5', '-ExecutorModels', 'gpt-5.5,gpt-5.4')
$wrapper11 = Join-Path $p11 '.claude/scripts/codex-run.ps1'
$dryDefault = Invoke-PwshFile $wrapper11 @('-DryRun', '-Brief', 'test', '-Cwd', $p11)
Assert ($dryDefault.Code -eq 0 -and (($dryDefault.Output -join "`n") -match 'worker=sol model=gpt-5\.5')) 'dry run uses configured default worker and model'
$dryTerra = Invoke-PwshFile $wrapper11 @('-DryRun', '-Brief', 'test', '-Cwd', $p11, '-Worker', 'terra')
Assert ($dryTerra.Code -eq 0 -and (($dryTerra.Output -join "`n") -match 'worker=terra model=gpt-5\.4')) 'dry run resolves terra model'
$dryNoBrief = Invoke-PwshFile $wrapper11 @('-DryRun', '-Cwd', $p11, '-Worker', 'terra')
Assert ($dryNoBrief.Code -eq 0 -and (($dryNoBrief.Output -join "`n") -match 'brief=<none: dry run>')) 'dry run works without a brief'
$noBriefReal = Invoke-PwshFile $wrapper11 @('-Cwd', $p11, '-Worker', 'terra')
Assert ($noBriefReal.Code -ne 0 -and (($noBriefReal.Output -join "`n") -match 'Provide -BriefFile')) 'real run without a brief still fails fast'
$dryUnknown = Invoke-PwshFile $wrapper11 @('-DryRun', '-Brief', 'test', '-Cwd', $p11, '-Worker', 'nope')
Assert ($dryUnknown.Code -ne 0 -and (($dryUnknown.Output -join "`n") -match 'Configured workers: sol, terra, luna')) 'unknown worker fails and lists configured slots'
$dryOverride = Invoke-PwshFile $wrapper11 @('-DryRun', '-Brief', 'test', '-Cwd', $p11, '-Worker', 'terra', '-Model', 'gpt-5.4-mini')
Assert ($dryOverride.Code -eq 0 -and (($dryOverride.Output -join "`n") -match 'worker=terra model=gpt-5\.4-mini')) 'explicit model overrides configured worker model'
$dryLunaAllowed = Invoke-PwshFile $wrapper11 @('-DryRun', '-Brief', 'test', '-Cwd', $p11, '-Worker', 'luna', '-Effort', 'ultra')
Assert ($dryLunaAllowed.Code -eq 0) 'ultra is allowed when luna slot maps to a model without -luna suffix'
Run @('-Project', $p11, '-ExecutorModels', 'gpt-5.6-sol,gpt-5.6-terra,gpt-5.6-luna')
$dryLunaGuard = Invoke-PwshFile $wrapper11 @('-DryRun', '-Brief', 'test', '-Cwd', $p11, '-Worker', 'luna', '-Effort', 'ultra')
Assert ($dryLunaGuard.Code -ne 0 -and (($dryLunaGuard.Output -join "`n") -match 'Luna caps at -Effort max')) 'ultra guard follows the resolved model suffix'

"== T12 installed reminder hook =="
Run @('-Project', $p11, '-ExecutorModels', 'gpt-5.5,gpt-5.4')
$hook11 = Join-Path $p11 '.claude/hooks/codex-reminder.ps1'
$oldProjectDir = $env:CLAUDE_PROJECT_DIR
try {
    $env:CLAUDE_PROJECT_DIR = $p11
    $hookCustom = Invoke-PwshFile -Path $hook11 -Arguments @() -InputText '{}'
    Assert ($hookCustom.Code -eq 0 -and $hookCustom.Output[0].Contains('Claude Opus 5 plans ->')) 'hook first line uses configured planner label'
    Assert ((($hookCustom.Output -join "`n") -match 'terra=gpt-5\.4') -and (($hookCustom.Output -join "`n") -match 'Planner model for this project: claude-opus-5')) 'hook includes configured workers and planner model note'

    $p12Current = NewProj 'proj12-current'
    Run @('-Project', $p12Current)
    $env:CLAUDE_PROJECT_DIR = $p12Current
    $hookCurrent = Invoke-PwshFile -Path (Join-Path $p12Current '.claude/hooks/codex-reminder.ps1') -Arguments @() -InputText '{}'
    Assert ($hookCurrent.Code -eq 0 -and (($hookCurrent.Output -join "`n") -notmatch 'Planner model for this project:')) 'current-session planner omits planner model line'
}
finally {
    $env:CLAUDE_PROJECT_DIR = $oldProjectDir
}

"== T13 no prompt without -Interactive =="
$p13 = NewProj 'proj13'
$noPrompt = Invoke-PwshFile $inst @('-Project', $p13) ''
Assert ($noPrompt.Code -eq 0 -and (Test-Path (Join-Path $p13 '.claude/codex-orchestration.json'))) 'redirected empty stdin install completes without prompting'

""
if ($script:fails -eq 0) { "ALL PASS" } else { "$($script:fails) FAILURE(S)"; exit 1 }
