# 设计取舍

## 目标

让 Claude Code 当**规划 + 验收**的大脑，把**实现**显式委派给 Codex CLI 的无头 worker，形成 `规划 → 委派 → 验收 → 迭代` 闭环，并支持并行多 worker。Claude 的上下文预算稀缺，Codex 的不稀缺：worker 花在探索与实现上的每个 token 都是 Claude 省下的。

非目标（YAGNI）：不做 Codex-as-MCP-server、不做 Claude subagent 包装层、不自动路由（只显式触发）、不锁模型、不上硬拦截、不写任何用户级配置。

## 数据流

```
Claude ──规划 + 拆解──▶ 简报 .codex/brief.md
                              │
        codex-run.ps1 → codex exec --sandbox workspace-write -m gpt-5.6-<worker>
                              │  改文件 / 跑命令（沙箱内、无需批准、不阻塞）
                              ▼
          -o .codex/result-<ts>.md + git diff ──▶ Claude 验收（diff + 自己跑测试）
                              │
             接受 ──或──▶ codex exec resume（回灌意见，同会话迭代）
```

并行 = N 个独立任务 → N 个 `git worktree` → N 个后台 `codex exec` → Claude 逐个验收并集成。**并行不用 Claude 自己的 subagent**：主会话直接后台并发 `codex exec`，省掉为包一层而多付的 Claude 调用。

## 为什么是这几个文件

| 文件 | 单一职责 |
|---|---|
| `scripts/codex-run.ps1` | 调用契约的唯一实现：简报走 stdin（避开 PowerShell 引号与非 ASCII 问题）、统一 flags、回收 `-o` 结果与退出码、`-Resume` 同会话迭代 |
| `commands/codex.md` | 单任务原语 |
| `commands/codex-fanout.md` | worktree 隔离 + 后台并发 |
| `commands/codex-flow.md` | 完整闭环（规划 → 确认 → 委派 → 验收 → 迭代） |
| `scripts/codex-reminder.ps1` | `UserPromptSubmit` 每轮一句温和提醒 |
| `assets/claude-md-block.md` | 项目 `CLAUDE.md` 策略块 |
| `codex-skills/comment-discipline/` | worker 侧 Codex 技能：注释纪律 |
| `scripts/install.ps1` | 把以上装进**一个项目**（`.claude/`、`CLAUDE.md`、`.agents/skills/`），可重跑、可卸载 |
| `SKILL.md` | 以上全部的索引与规则正文，按描述自动触发 |

## 为什么只装项目级

- 规则是团队对**这个仓库**的工作约定，放进仓库才能随代码一起评审、共享、回滚。
- 不碰 `~/.claude` 与 `~/.codex`，就不会覆盖使用者自己的全局策略；个人例外（哪些工作必须亲手做）留在个人 `~/.claude/CLAUDE.md` 或项目 CLAUDE.md 的其他段落里声明。
- hook 命令用 `$CLAUDE_PROJECT_DIR` 引用脚本，`settings.json` 提交后在任何机器上都能跑（Windows 上已实测展开）。
- worker 侧技能放 `.agents/skills/`：这是 Codex 文档写明的仓库级位置（从工作目录向上扫到仓库根），0.144 实测 `.codex/skills/` 也能被发现，但 `.codex/` 已经被包装脚本当作草稿目录并整体 gitignore，分开放更干净。

## 「确保一直照此工作」为什么分层

对话内的嘱咐会被压缩、被遗忘。CLAUDE.md 每个会话重载、hook 每轮必跑、skill 按描述触发——它们活在 harness 层，不随上下文蒸发。

- **L1 项目 `CLAUDE.md` 策略块**：基线倾向。
- **L2 项目 `.claude/settings.json` 的 `UserPromptSubmit` hook**：强倾向，抗长会话漂移。
- **不锁模型**：只提醒「你是规划者」，不写 `settings.json` 的 `model` 字段。
- **不上 L3 硬拦截**（`PreToolUse` deny 源码编辑）：保留为将来升级位。

## 调用契约要点

- `--sandbox workspace-write`：只能改工作区内文件；`codex exec` 非交互模式下审批策略默认 `never`，不会弹窗阻塞；越界写入被沙盒挡（`--add-dir` 放行）。
- `-o <file>`：Codex 最终消息落盘，编排者读文件而不是读整段 transcript。
- `exec resume --last` / `<session-id>`：回灌意见到同一会话，带上下文，比重开省。`resume` 没有 `-C`，按 cwd 过滤会话，所以包装脚本会先 `Push-Location`。
- 登录走 ChatGPT 订阅，无 API key。

## 来源

本 skill 源自作者 2026 年 6–8 月在两个仓库上的实践（Windows / PowerShell 主线，外加一次 macOS 上的受控实验——见本仓库的 `codex-dispatch` / `codex-execute`）。实战坑见 `worker-traps.md`。
