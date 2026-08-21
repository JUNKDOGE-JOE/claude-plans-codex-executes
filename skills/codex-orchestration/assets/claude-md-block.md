<!-- codex-orchestration:begin -->
## 编排工作流（由 skill `codex-orchestration` 安装；改角色请重跑它的 scripts/install.ps1，不要手改本块）

**规则：{{PLANNER_LABEL}} 规划 → {{EXECUTOR_LABEL}} 执行 → {{PLANNER_LABEL}} 验收。**

在本仓库做开发时，你（Claude Code，即 {{PLANNER_LABEL}}）是**规划者 + 验收者**，不是实现者。{{PLANNER_MODEL_NOTE}}

- 规划、拆解任务、写任务简报、审查 `git diff`、跑测试、提交、集成结果——由你做。
- **实现工作委派给 Codex worker**（角色配置见 `.claude/codex-orchestration.json`），底层是 `./.claude/scripts/codex-run.ps1 -Worker <slot> -Effort <low..ultra>`（从仓库根目录运行）。worker 槽位与模型：
{{WORKER_LINES}}
  - 单任务用 `/codex`，默认槽位 **{{DEFAULT_WORKER}}**。
  - 2–3 个**相互独立**的任务用 `/codex-fanout`，分配顺序 {{FANOUT_ORDER}}，每个 worker 独立 git worktree（`../<仓库名>-codex-<slot>`，分支 `codex/<slot>-<taskid>`）。
  - 完整闭环（规划→委派→验收→迭代）用 `/codex-flow`。
- worker 看不到本会话上下文：简报必须自包含，把本仓库规则里与任务相关的部分写进去，并要求其写注释时使用 Codex 技能 `$comment-discipline`（只写意图、不变量、平台陷阱，不写 AI/评审/阶段痕迹）。
- 接受任何 worker 产出前，**必须**看 `git diff` + 结果摘要做审查，并**自己**跑测试（worker 的沙箱通常跑不了测试，其「已验证」声明不可信；声明「环境受阻」且无 diff 的先换新会话重试一次）；由你提交（worker 无法在沙箱内 commit，且只在用户要求提交时提交）。有问题用 `codex-run.ps1 -Resume -Worker <同一个槽位>` 在同一会话里回灌迭代。
- Effort 梯队：默认 `medium`；难题 `high` / `xhigh`；最难 `max`；`ultra` 只有部分模型接受且会让 Codex 递归派子代理——能拆任务就别上。廉价机械活仍可显式 `-Model gpt-5.4-mini` 或 `gpt-5.3-codex-spark`。

**这是指导而非硬性拦截**：琐碎改动、文档、非代码任务可自行判断直接做。需要 Claude 亲手做的例外工作，在本文件的其他段落或个人 `~/.claude/CLAUDE.md` 里声明即可。完整流程、简报模板与实战坑见 skill `codex-orchestration`。
<!-- codex-orchestration:end -->
