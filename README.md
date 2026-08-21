# claude-plans-codex-executes

**Claude Code（Fable 5）规划与验收 → Codex 的 GPT-5.6 worker（Sol / Luna / Terra）执行。**

这条本机开发编排规则被整合成一个可安装的 Claude Code skill：[`skills/codex-orchestration`](skills/codex-orchestration/SKILL.md)。装上以后，任何仓库里 Claude 都会：先写自包含的任务简报 → 通过 `codex-run.ps1` 把实现交给 Codex worker → 自己审 `git diff`、自己跑测试 → 由自己提交；并行任务各开一个 git worktree。

## 一行安装

把这句贴给任意一台机器上的 Claude Code（该机器需已 `gh auth login` 且能访问本私有仓库；Windows 需 PowerShell 7）：

```text
安装 https://github.com/JUNKDOGE-JOE/claude-plans-codex-executes ：用 gh 克隆到临时目录，运行 skills/codex-orchestration/scripts/install.ps1（没有 pwsh 就按 README「装了什么」那张表手动拷贝），装完重开会话确认 /codex、/codex-fanout、/codex-flow 与 skill codex-orchestration 可用
```

或者自己在 PowerShell 7 里跑同样的事：

```powershell
$d="$env:TEMP\claude-plans-codex-executes"; if (Test-Path $d) { Remove-Item $d -Recurse -Force }; gh repo clone JUNKDOGE-JOE/claude-plans-codex-executes $d -- --depth 1; pwsh -NoProfile -ExecutionPolicy Bypass -File "$d\skills\codex-orchestration\scripts\install.ps1"
```

重跑同一条命令即为更新；加 `-Uninstall` 即为卸载（手写的 CLAUDE.md 内容与被改过的文件都会保留为 `.bak-<时间戳>`）。先演练不落盘：`install.ps1 -UserHome <任意空目录>`。

前提：Codex CLI ≥ 0.144（`npm i -g @openai/codex`，`codex login` 走 ChatGPT 订阅，模型 id `gpt-5.6-sol|luna|terra`）。macOS 上 `codex` 二进制在 `ChatGPT.app` 里、默认不在 PATH，要先链到 PATH。

## 装了什么

| 源（本仓库） | 目标 | 作用 |
|---|---|---|
| `skills/codex-orchestration/` | `~/.claude/skills/codex-orchestration/` | skill 本体：规则正文 + 简报模板 + 实战坑 + 设计取舍，按描述自动触发 |
| `…/commands/codex*.md` | `~/.claude/commands/` | `/codex`（单任务，默认 Sol）、`/codex-fanout`（2–3 个独立任务并行，Sol→Terra→Luna）、`/codex-flow`（完整闭环） |
| `…/scripts/codex-run.ps1` | `~/.claude/scripts/codex-run.ps1` | worker 包装：`codex exec --sandbox workspace-write -m gpt-5.6-<worker>`，简报走 stdin，`-Resume` 同会话迭代 |
| `…/scripts/codex-reminder.ps1` | `~/.claude/hooks/` + `settings.json` 的 `UserPromptSubmit` | 每轮一句提醒，抗长会话漂移；项目自带同名 hook 时静默 |
| `…/assets/claude-md-block.md` | `~/.claude/CLAUDE.md`（追加，带标记） | 策略块；已有手写策略时不动 |
| `…/codex-skills/comment-discipline/` | `~/.codex/skills/comment-discipline/` | worker 侧 Codex 技能：注释只写意图 / 不变量 / 平台陷阱 |

## 用法速记

```text
/codex 给 plugin/panel 的 Provider 选择器加键盘导航，照 src/components/Menu.jsx 的模式
/codex-fanout 三件独立事：A 修 #231 的超时；B 给 ae_read 补 schema 测试；C 把 docs/ 里的旧 helper 引用清掉
/codex-flow 把 nativeExec 的返回值改成 typed envelope（先出计划再派）
```

- Effort：默认 `medium`；难 `high` / `xhigh`；最难 `max`；`ultra` 只 Sol / Terra 接受且会递归派子代理——能拆就拆。
- 例外：shader 创作（GLSL / `@dynamicfx` / Shadertoy 移植 / 视觉调试）全程 Claude 亲自做，不委派；琐碎改动与文档也可直接做。
- 验收铁律：worker 的「已跑测试」不可信，自己跑；不审 diff 不接受；只有编排者 commit。

## 仓库结构

```
skills/
  codex-orchestration/        ← 当前机器级规则（Windows / PowerShell，2026-08）
    SKILL.md
    scripts/   install.ps1 · codex-run.ps1 · codex-reminder.ps1
    commands/  codex.md · codex-fanout.md · codex-flow.md
    references/  brief-template.md · worker-traps.md · design-rationale.md
    assets/    claude-md-block.md
    codex-skills/comment-discipline/   （装到 ~/.codex/skills/）
  codex-dispatch/             ← 2026-07 macOS 变体：bash dispatch.sh + JSON receipt schema（Claude 侧）
  codex-execute/              ← 同上，worker 侧的执行纪律
```

两代变体讲的是同一条规则。`codex-orchestration` 是现在机器上真正在跑的那套；`codex-dispatch` 的 receipt schema、`NON-GOALS` / `STOP-AND-ASK`、「给要提交的线一个 clone 而不是 worktree」等经验已吸收进 `codex-orchestration/references/`。
