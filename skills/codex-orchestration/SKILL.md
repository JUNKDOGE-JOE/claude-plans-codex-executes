---
name: codex-orchestration
description: 本机开发编排规则「Claude Code (Fable) 规划与验收 → Codex GPT-5.6 worker (Sol / Luna / Terra) 执行」。Use before writing or changing any source code in a repository (features, bug fixes, refactors, tests, scripts) — plan it, brief it, delegate it to a Codex worker through codex-run.ps1, then review the diff and run the tests yourself. Also use when the user says /codex, 派给 codex, 让 Sol/Luna/Terra 做, fanout, 并行三路, or asks which worker or effort to pick. Not for shader authoring (GLSL, @dynamicfx, Shadertoy ports — always written by Fable directly), trivial edits, or pure documentation.
argument-hint: [任务描述 | fanout <目标> | flow <目标>]
---

# Claude plans → Codex executes

**规则：Fable 规划 → Sol / Luna / Terra 执行 → Fable 验收。**

你（Claude Code，Fable 5）是**规划者 + 验收者**，不是实现者。实现源码由 Codex 无头 worker 写；你写简报、审 `git diff`、跑测试、提交、集成。

## 1. 适用边界

| 你自己直接做 | 委派给 worker |
|---|---|
| 琐碎改动、文档、非代码任务 | 一切实现：功能、修 bug、重构、测试、脚本 |
| **Shader 创作全程自己做**：`@dynamicfx` shader、GLSL、Shadertoy 移植、`examples/*.glsl`、shader 编译报错与视觉调试、配套的 AE 现场验证循环（这是视觉与数值手感活，委派会丢上下文） | 围绕 shader 的常规代码（Rust / TS / Python / 脚本 / 测试）仍委派 |

- 这是强倾向，不是硬拦截。
- 各仓库自己的 CLAUDE.md（阅读顺序、里程碑、ADR / 证据政策）在本规则之上继续完整生效，冲突时以仓库规则为准。

## 2. 三个入口

| 命令 | 用途 | worker |
|---|---|---|
| `/codex <任务>` | 单任务闭环：简报 → 委派 → 审 diff → 迭代 | Sol（默认） |
| `/codex-fanout <目标>` | 2–3 个**相互独立**的任务并行，每个 worker 一个 git worktree | 任务 1 → Sol、2 → Terra、3 → Luna |
| `/codex-flow <目标>` | 完整闭环：规划 → 和用户确认 → 委派 → 验收 → 迭代 → 收尾 | 按拆分结果 |

三个命令由 `scripts/install.ps1` 装进 `~/.claude/commands/`；完整步骤见 `${CLAUDE_SKILL_DIR}/commands/`。没装命令时照 §4–§6 手动走同一流程。

## 3. Worker 与 effort

Sol / Luna / Terra = GPT-5.6 的三个变体，Codex CLI 模型 id `gpt-5.6-sol` / `gpt-5.6-luna` / `gpt-5.6-terra`，走 Codex 登录态运行（无 API key）。

- **分配**：单任务默认 Sol；fanout 顺序 Sol → Terra → Luna。按任务性质挑时可参考：要先提出假设再验证（跨层设计、怪 bug 根因）→ Sol；范围清楚但需要判断（写 handler、修已复现的 bug、写测试）→ Terra；方案已知只是打字（跑测试、格式化、按说明改）→ Luna。
- **effort**：默认 `medium`；难题 `high` / `xhigh`；最难 `max`；`ultra` 只有 Sol / Terra 接受（Luna 上限 `max`）。⚠ `ultra` 会让 Codex 自己再派子代理（2026-07 macOS 实测），成本与可控性都差——任务大到想上 ultra，先拆任务。
- effort 是主要成本杠杆；`-Resume` 每轮都会重发整段上下文，回灌意见要一次说全。
- 廉价机械活（改名 / 样板 / 格式化）可显式 `-Model gpt-5.4-mini` 或 `gpt-5.3-codex-spark`。

## 4. 简报（决定产出质量）

写到 `.codex/brief.md`（包装脚本会建目录并让它自我 gitignore）。**worker 看不到本会话**，简报必须自包含：

```
## 任务            一句话说清要做什么
## 背景与相关文件   具体路径、现有模式；把仓库规则里与任务相关的部分原文嵌进去
                    （例如 ADR / 证据政策 / 「新增持久字段先开 ADR」）
## 约束            遵循现有风格与本地 helper API；不碰无关代码；**不要 commit**；
                    列出「不要动」的文件；写注释用 Codex 技能 `$comment-discipline`
## 验收标准         可验证的产出 + 要跑的精确测试命令
## 完成后          总结改了哪些文件、为什么、如何验证
                    （跑了什么、结果如何；跑不了的如实写「未运行」）
```

完整模板与加强项（非目标 / 遇到什么必须停下来报告）见 `${CLAUDE_SKILL_DIR}/references/brief-template.md`。

## 5. 调用

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\codex-run.ps1" -BriefFile .codex/brief.md -Worker sol -Effort medium
```

没跑过 `install.ps1` 时直接用 `${CLAUDE_SKILL_DIR}/scripts/codex-run.ps1`（同一个文件）。

| 参数 | 作用 |
|---|---|
| `-Worker sol\|luna\|terra` | 选 worker（→ `-m gpt-5.6-<worker>`）；`-Model` 显式给出时覆盖 |
| `-Effort low\|medium\|high\|xhigh\|max\|ultra` | 推理强度；Luna + ultra 直接抛错 |
| `-BriefFile <path>` / `-Brief "<文本>"` | 简报来源；简报经 stdin 传给 Codex，避开引号与非 ASCII 问题 |
| `-Cwd <repo 或 worktree>` | 工作目录（默认当前）；fanout 必带 |
| `-AddDir <dir>` | 额外可写目录；`-Bypass` 关沙箱（慎用） |
| `-Resume [-SessionId <id>]` | 在同一 Codex 会话里回灌意见（带上下文）；默认按 cwd 取最近会话 |

内部等价于 `codex exec --sandbox workspace-write -m <model> -c model_reasoning_effort=<effort> -o .codex/result-<ts>.md -`；脚本回显退出码与结果全文。

迭代：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\scripts\codex-run.ps1" -Resume -Brief "<具体修改意见>" -Worker sol
```

长反馈用 `-BriefFile`；worktree 里迭代要带 `-Cwd <worktree>`；要钉死某个会话用 `-SessionId`。

## 6. 验收（必做，不可跳过）

1. `git status` + `git diff`（worktree 用 `git -C <wt> diff`），逐项对照验收标准。
2. **自己跑测试**，带硬超时。worker 的「已跑、通过」不可信：沙箱经常起不了子进程 / 跑不了测试运行器。worker 声明「环境受阻」且没有 diff（退出码仍是 0）→ 先换新会话重试一次，再考虑自己做。
3. 非平凡 diff 走 `/code-review`；复制 / 搬运类任务要和源文件逐字节比对（worker 会悄悄简化）。
4. 通过 → 告诉用户 worker 改了什么、你审了什么。**由你 commit**，且只在用户要求提交时提交；worker 在沙箱里 commit 不了（worktree 的 git 元数据在沙箱外）。
5. 不通过 → `-Resume` 回灌给**同一个** worker。永不接受没审过的改动；永不汇报自己没观察到的结果。

## 7. 并行 fanout 要点

- 只并行真正独立的任务（无共享文件、无先后依赖）；超过 3 个就排队给先完成的 worker；不独立就改用 `/codex` 串行。拆分先和用户确认。
- 每个任务：`git worktree add ../<repo>-codex-<worker> -b codex/<worker>-<taskid>`。worktree 没有主检出的未跟踪文件（计划、node_modules、本地 CLAUDE.md、设计导出）→ 把 worker 需要的都拷进 `<wt>/.codex/`；每份简报给出明确的「不要动」文件清单，三路 diff 才不会相撞。
- **禁止**在 worker 运行期间把主检出的 `node_modules` 以 junction 接进 worktree：worker 的 `npm ci` 会穿透 junction 清空主检出。收尾先摘 junction 再 `git worktree remove`。
- 后台启动（`-Cwd <wt>`）；完成通知迟迟不来就直接读 `<wt>/.codex/result-*.md`，杀掉残留的 `codex` / `node` 进程再删 worktree。
- 三路合进**一个集成分支**：你解一次冲突、在合并态跑全套件、开一个 PR，比三个 PR 互相 rebase 省事。

## 8. 实战坑速查

全部在 `${CLAUDE_SKILL_DIR}/references/worker-traps.md`：沙箱时好时坏起不了进程、worker 写的异步测试挂死整套件、junction 惨案、codex 进程写完结果不退出、copy 任务被悄悄简化、CLI 版本门槛、`-Resume` 会话匹配等。接手一个新仓库前扫一遍。

## 9. 这套规则如何「一直生效」

- L1：`~/.claude/CLAUDE.md` 策略块——每个会话与每次上下文压缩后重载。
- L2：`UserPromptSubmit` hook（`~/.claude/hooks/codex-reminder.ps1`）——每轮注入一句提醒，抗长会话漂移；项目自带同名 hook 时自动静默。
- 本 skill 按描述自动触发，给出完整流程与引用。
- 不锁模型、不上硬拦截（`PreToolUse` deny 留作将来升级位）。

`scripts/install.ps1` 一次装齐以上全部外加 worker 侧的 Codex 技能 `comment-discipline`；设计取舍与演进史见 `${CLAUDE_SKILL_DIR}/references/design-rationale.md`。
