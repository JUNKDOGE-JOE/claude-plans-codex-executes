# 设计取舍与演进史

## 目标

让 Claude Code（Fable 5）当**规划 + 验收**的大脑，把**实现**显式委派给本机 Codex CLI 的无头 worker，形成 `规划 → 委派 → 验收 → 迭代` 闭环，并支持并行多 worker。Claude 的上下文预算稀缺，Codex 的不稀缺：worker 花在探索与实现上的每个 token 都是 Claude 省下的。

非目标（YAGNI）：不做 Codex-as-MCP-server、不做 Claude subagent 包装层、不自动路由（只显式触发）、不锁模型、不上硬拦截。

## 数据流

```
Fable ──规划 + 拆解──▶ 简报 .codex/brief.md
                              │
        codex-run.ps1 → codex exec --sandbox workspace-write -m gpt-5.6-<worker>
                              │  改文件 / 跑命令（沙箱内、无需批准、不阻塞）
                              ▼
          -o .codex/result-<ts>.md + git diff ──▶ Fable 验收（diff + 自己跑测试）
                              │
             接受 ──或──▶ codex exec resume（回灌意见，同会话迭代）
```

并行 = N 个独立任务 → N 个 `git worktree` → N 个后台 `codex exec` → Fable 逐个验收并集成。**并行不用 Claude 自己的 subagent**：主会话直接后台并发 `codex exec`，省掉为包一层而多付的 Claude 调用。

## 为什么是这几个文件

| 文件 | 单一职责 |
|---|---|
| `scripts/codex-run.ps1` | 调用契约的唯一实现：简报走 stdin（避开 PowerShell 引号与非 ASCII 问题）、统一 flags、回收 `-o` 结果与退出码、`-Resume` 同会话迭代 |
| `commands/codex.md` | 单任务原语 |
| `commands/codex-fanout.md` | worktree 隔离 + 后台并发 |
| `commands/codex-flow.md` | 完整闭环（规划 → 确认 → 委派 → 验收 → 迭代） |
| `scripts/codex-reminder.ps1` | `UserPromptSubmit` 每轮一句温和提醒 |
| `assets/claude-md-block.md` | `~/.claude/CLAUDE.md` 策略块 |
| `codex-skills/comment-discipline/` | worker 侧 Codex 技能：注释纪律 |
| `SKILL.md` | 以上全部的索引与规则正文，按描述自动触发 |

## 「确保一直照此工作」为什么分层

对话内的嘱咐会被压缩、被遗忘。CLAUDE.md 每个会话重载、hook 每轮必跑、skill 按描述触发——它们活在 harness 层，不随上下文蒸发。

- **L1 `CLAUDE.md` 策略块**：基线倾向。
- **L2 `UserPromptSubmit` hook**：强倾向，抗长会话漂移；项目自带同名 hook 时用户级副本自动静默，避免双重注入。
- **不锁模型**：只提醒「你是规划者」，不写 `settings.json` 的 `model` 字段，保留按项目选模型的自由。
- **不上 L3 硬拦截**（`PreToolUse` deny 源码编辑）：保留为将来升级位。

## 调用契约要点

- `--sandbox workspace-write`：只能改工作区内文件；`codex exec` 非交互模式下审批策略默认 `never`，不会弹窗阻塞；越界写入被沙盒挡（`--add-dir` 放行）。
- `-o <file>`：Codex 最终消息落盘，编排者读文件而不是读整段 transcript。
- `exec resume --last` / `<session-id>`：回灌意见到同一会话，带上下文，比重开省。`resume` 没有 `-C`，按 cwd 过滤会话，所以包装脚本会先 `Push-Location`。
- 登录走 ChatGPT 订阅，无 API key。

## 演进史

| 日期 | 事件 |
|---|---|
| 2026-06-10 | 在 `after-effects-mcp` 设计并验证：Codex `gpt-5.5` fast 档，`/codex` `/codex-flow` `/codex-fanout` + 包装脚本 + hook。设计存档 `docs/superpowers/specs/2026-06-10-codex-orchestration-design.md` |
| 2026-06-11/12 | 首批真实 fanout（4 worker）：沙箱起不了子进程、跑不了 pytest、worktree 里 commit 不了 → 确立「编排者跑测试 + 提交」的分工；copy 任务被悄悄简化 → 「逐字节比对」规则；worker 异步测试挂死套件 → 「硬超时」规则 |
| 2026-06-13 | 用户暂停（切到 Opus），配置改名 `.disabled` 保留 |
| 2026-07-25 | macOS 上独立演化出 `codex-dispatch` / `codex-execute`（bash + JSON receipt schema，模型按性质分 Sol / Terra / Luna，封禁 `ultra`）——见本仓库 `skills/codex-dispatch/`、`skills/codex-execute/` |
| 2026-08-19 | 用户重启并改向：worker = GPT-5.6 三变体 Sol / Luna / Terra；包装脚本加 `-Worker`；effort 加 `max` / `ultra`；同日三路 fanout 交付 Phase 0 |
| 2026-08-20 | junction 惨案 → 「worker 运行期间永不接 junction」 |
| 2026-08-21 | 推广到本机全局 `~/.claude`（用户明确例外：shader 创作全 Fable）；同日整合成本 skill 并同步到本仓库 |
