# claude-plans-codex-executes

**规划/审查模型（Claude Code 会话）规划与验收 → 开发/执行模型（Codex worker）执行。**

这条开发编排规则被整合成一个可安装的 Claude Code skill：[`skills/codex-orchestration`](skills/codex-orchestration/SKILL.md)。装进一个项目以后，Claude 在这个仓库里会：先写自包含的任务简报 → 通过 `.claude/scripts/codex-run.ps1` 把实现交给 Codex worker → 自己审 `git diff`、自己跑测试 → 由自己提交；并行任务各开一个 git worktree。

**谁规划、谁执行由你定**：第一次在项目里使用时，Claude 会问两个问题——规划/审查用哪个 Claude 模型、开发/执行用哪个（些）Codex 模型——答案写进项目的 `.claude/codex-orchestration.json`，wrapper、提醒 hook 和 CLAUDE.md 策略块都按它走。

**只装项目级**：所有文件都写进目标仓库（`.claude/`、`CLAUDE.md`、`.agents/skills/`），不碰 `~/.claude` 和 `~/.codex`。要不要把它们提交进版本库，由项目自己决定。

## 一行安装

在目标项目根目录打开 Claude Code，把这句贴给它（机器需装有 git 与 PowerShell 7）：

```text
在当前项目安装 https://github.com/JUNKDOGE-JOE/claude-plans-codex-executes ：先问我两个问题——①规划/审查模型用哪个（当前会话的模型 / Claude Fable 5 / Opus 5 / Sonnet 5）②开发/执行模型用哪个（Codex GPT-5.6 Sol/Terra/Luna / GPT-5.5 / GPT-5.4 / 自定义）；然后 git clone 到临时目录，在项目根目录运行 skills/codex-orchestration/scripts/install.ps1 -Project . -PlannerModel <答案1的模型id或current> -ExecutorModels <答案2的模型id，逗号分隔>（只写项目的 .claude/、CLAUDE.md、.agents/skills/，不碰 ~/.claude；没有 pwsh 就按 README「装了什么」那张表手动拷贝），装完重开会话确认 /codex、/codex-fanout、/codex-flow 可用
```

或自己在项目根目录的 PowerShell 7 里跑（`-Interactive` 会用菜单问你同样两个问题）：

```powershell
$d="$env:TEMP\claude-plans-codex-executes"; if (Test-Path $d) { Remove-Item $d -Recurse -Force }; git clone --depth 1 https://github.com/JUNKDOGE-JOE/claude-plans-codex-executes $d; pwsh -NoProfile -ExecutionPolicy Bypass -File "$d\skills\codex-orchestration\scripts\install.ps1" -Project . -Interactive
```

重跑同一条命令即为更新（不带角色参数时保留你已有的角色配置）；加 `-Uninstall` 即为卸载（手写的 CLAUDE.md 内容与被改过的文件都会保留为 `.bak-<时间戳>`）。想先演练，把 `-Project` 指向任意一个临时 git 仓库。

前提：Codex CLI ≥ 0.144（`npm i -g @openai/codex`，`codex login` 走 ChatGPT 订阅）。macOS 上 `codex` 二进制在 `ChatGPT.app` 里、默认不在 PATH，用 `-CodexCommand <路径>` 指过去；安装器本身需要 `pwsh`（`brew install powershell`）。

## 角色配置

`<项目>/.claude/codex-orchestration.json`，由安装器生成，改角色就重跑安装器（或让 Claude 重跑）：

```json
{
  "version": 1,
  "planner": { "label": "Claude Opus 5", "model": "claude-opus-5" },
  "executor": {
    "label": "Codex GPT-5.6 (Sol / Terra / Luna)",
    "codexCommand": "codex",
    "workers": { "sol": "gpt-5.6-sol", "terra": "gpt-5.6-terra", "luna": "gpt-5.6-luna" },
    "defaultWorker": "sol",
    "fanoutOrder": ["sol", "terra", "luna"]
  }
}
```

- **planner** = 规划/审查模型，就是这个 Claude Code 会话跑的模型。`model` 为 `null`（`-PlannerModel current`）表示不锁定；填了具体 id（如 `claude-opus-5`）安装器会把项目 `.claude/settings.json` 的 `model` 设成它，会话跑别的模型时 hook 会提醒一次。
- **executor** = 开发/执行模型：三个 worker 槽位 `sol` / `terra` / `luna` 各对应一个 Codex 模型 id（`-ExecutorModels gpt-5.5` 表示三个槽位都跑 GPT-5.5；`-ExecutorModels a,b` 表示 sol=a、terra=b、luna=b）。`defaultWorker` 是单任务用的槽位，`fanoutOrder` 是并行时的分配顺序。
- 改完想看效果：`pwsh -File .\.claude\scripts\codex-run.ps1 -DryRun -Worker terra` 只打印解析出的模型与命令行，不调用 Codex。

```powershell
# 例：规划用 Opus 5，执行全部用 GPT-5.5
pwsh -NoProfile -ExecutionPolicy Bypass -File .\.claude\skills\codex-orchestration\scripts\install.ps1 -Project . -PlannerModel claude-opus-5 -ExecutorModels gpt-5.5
```

## 装了什么

| 源（本仓库） | 目标（项目内） | 作用 |
|---|---|---|
| `skills/codex-orchestration/` | `.claude/skills/codex-orchestration/` | skill 本体：规则正文 + 简报模板 + 实战坑 + 设计取舍，按描述自动触发 |
| （安装器生成） | `.claude/codex-orchestration.json` | 角色配置：规划模型、worker 槽位 → Codex 模型、默认槽位、fanout 顺序 |
| `…/commands/codex*.md` | `.claude/commands/` | `/codex`（单任务）、`/codex-fanout`（2–3 个独立任务并行）、`/codex-flow`（完整闭环）；首次使用会先问角色 |
| `…/scripts/codex-run.ps1` | `.claude/scripts/codex-run.ps1` | worker 包装：`codex exec --sandbox workspace-write -m <配置的模型>`，简报走 stdin，`-Resume` 同会话迭代，`-DryRun` 预览 |
| `…/scripts/codex-reminder.ps1` | `.claude/hooks/` + `.claude/settings.json` 的 `UserPromptSubmit` | 每轮一句带角色的提醒，抗长会话漂移；命令用 `$CLAUDE_PROJECT_DIR` 引用脚本，提交后在任何机器上都能跑 |
| `…/assets/claude-md-block.md` | `CLAUDE.md`（追加，带标记） | 策略块，按角色配置渲染；已有手写策略时不动 |
| `…/codex-skills/comment-discipline/` | `.agents/skills/comment-discipline/` | worker 侧 Codex 技能：注释只写意图 / 不变量 / 平台陷阱（Codex 从仓库根开始扫描 `.agents/skills/`） |

## 用法速记

```text
/codex 给设置面板的下拉框加键盘导航，照 src/components/Menu.jsx 的模式
/codex-fanout 三件独立事：A 修 #231 的超时；B 给 read 接口补 schema 测试；C 清掉 docs/ 里的旧 helper 引用
/codex-flow 把 exec 的返回值改成 typed envelope（先出计划再派）
```

- Effort：默认 `medium`；难 `high` / `xhigh`；最难 `max`；`ultra` 只有部分模型接受且会递归派子代理——能拆就拆。
- 验收铁律：worker 的「已跑测试」不可信，自己跑；不审 diff 不接受；只有编排者 commit。
- 琐碎改动、文档、非代码任务可以直接做，不必委派。

## 例外怎么声明

skill 本身不内置任何「不委派」清单。需要 Claude 亲手做的工作（例如依赖视觉或数值手感、需要紧密反馈循环的东西），写进项目 `CLAUDE.md` 的其他段落，或个人 `~/.claude/CLAUDE.md`：

```markdown
**例外——以下工作不委派，由 Claude 直接做：** <列出来>；围绕它们的常规实现仍走委派。
```

三个 `/codex*` 命令和 hook 都会尊重这种声明。

## 仓库结构

```
skills/
  codex-orchestration/        ← 当前这套（Windows / PowerShell 主线，项目级安装）
    SKILL.md
    scripts/   install.ps1 · codex-run.ps1 · codex-reminder.ps1
    commands/  codex.md · codex-fanout.md · codex-flow.md
    references/  brief-template.md · worker-traps.md · design-rationale.md
    assets/    claude-md-block.md（按角色渲染的模板）
    codex-skills/comment-discipline/   （装到项目 .agents/skills/）
    tests/     install.tests.ps1（pwsh 一键自测：安装 / 更新 / 卸载 / 角色 / wrapper 解析 / hook）
  codex-dispatch/             ← 早期 macOS 变体：bash dispatch.sh + JSON receipt schema（Claude 侧）
  codex-execute/              ← 同上，worker 侧的执行纪律
```

两代变体讲的是同一条规则。`codex-dispatch` 的 receipt schema、`NON-GOALS` / `STOP-AND-ASK`、「给要提交的线一个 clone 而不是 worktree」等经验已吸收进 `codex-orchestration/references/`。
