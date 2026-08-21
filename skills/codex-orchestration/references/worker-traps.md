# Worker 实战坑（实践累计）

每条都来自一次真实翻车。接手新仓库前扫一遍；出现同样症状时先对号入座，别重新调试。

## 沙箱与进程

| 症状 | 真相 | 怎么办 |
|---|---|---|
| worker 报 `CreateProcessAsUserW failed: 5`，说自己「环境受阻」 | `codex exec --sandbox workspace-write` 在 Windows 上**时好时坏**地起不了子进程（pwsh / npm / uv 都可能），同一会话第二轮常常一条命令都跑不了；并发的兄弟 worker 可能完全正常 | worker 会退回用它的 `node_repl` MCP 或 `apply_patch` 完成编辑——这不影响 diff 质量，但它**绝对没跑过测试**。每轮都自己跑 |
| worker 声明受阻、退出码 0、**没有 diff** | 「已完成」的退出码不代表做了事；要读结果文本 | 先换**新会话**重试一次（新会话往往能自恢复），再考虑自己做 |
| 完成通知迟迟不来 | worker 写完 `result-*.md` 后 codex 父进程等一个挂死的子进程（典型：带定时器或长连接的测试进程），不退出 | 直接读 `<cwd>/.codex/result-*.md`；收尾 `Get-Process codex,node` 杀残留，否则 `git worktree remove` 报 Permission denied |
| worker 写的异步测试让整套件挂住 20+ 分钟 | worker 跑不了测试时会交出永不 resolve 的 await（例如等一个没人批准的 approval）；`node --test` 之类运行器没有默认超时 | 自己跑套件时**带硬超时**；后台运行的输出文件 60s 还是空的就杀掉进程树、按文件二分 |
| `codex exec` 在非 git 目录直接拒绝 | 设计如此 | 加 `--skip-git-repo-check`（包装脚本没带，临时目录实验时自己加） |
| stderr 有 `failed to load models cache: missing field base_instructions` | 良性噪音 | 忽略 |

## 验收

- **worker 的「已验证」永远只当参考。** 它跑不了测试的那一轮尤其要**逐行看 diff 的位置**：曾把一个 `let` 声明插错函数变成隐式全局，测试过不了才发现。
- **复制 / 搬运类任务要和源文件逐字节比对。** 沙箱挡住包管理器时 worker 手写过一个假的构建产物（有如实标注），还把「逐字拷贝 30 个组件」悄悄简化掉一半（丢 hover / press / a11y），靠 diff 源导出才抓到。
- worker 在 worktree 里 **commit 不了**：linked worktree 的 git 元数据在主仓库 `.git/worktrees/<name>/`，沙箱外。由编排者在各分支提交。若某条线必须自己提交，给它一个 `git clone --shared` 出来的独立克隆（`.git` 在工作区内）而不是 worktree。
- 一次迭代 `-Resume` 会重发整段上下文；意见一次说全，别挤牙膏。

## worktree 与 fanout

- worktree **没有**主检出的未跟踪文件：本地 CLAUDE.md、计划文档、`node_modules`、设计导出。简报要么嵌入，要么拷进 `<worktree>/.codex/`。
- **junction 惨案**：把主检出的 `node_modules` 用 NTFS junction 接进 worktree 后，worker 的 `npm ci` → rimraf 穿透 junction 把主检出的 `node_modules` 清空（构建工具消失、整套测试环境败掉）。规则：**worker 运行期间永远不接 junction / symlink**；要验收再接，用完先 `[System.IO.Directory]::Delete(path, $false)` 摘链接再 `git worktree remove`。`git worktree remove --force` 同样会穿透 junction 删目标内容。损伤恢复 = 主检出重新安装依赖。
- 每份简报给明确的「不要动」文件清单 → 四路并行零冲突是实测结果。
- 三路都往 `CHANGELOG` 加条目、都改同一文件的不同区域 → 用**一个集成分支**合三路、解一次冲突、合并态跑全套件、开一个 PR。
- `-Resume` 按 cwd 匹配最近会话：worktree 里迭代必须 `-Cwd <worktree>`；多条线并行时用 `-SessionId` 钉死；长反馈用 `-BriefFile`。
- worktree 里套件因缺依赖而失败是环境噪音，回主检出复跑。

## 模型与 CLI

- `gpt-5.6-sol / -luna / -terra` 在 codex-cli 0.144 实测可用；`ultra` 只 Sol / Terra 接受，Luna 上限 `max`。`ultra` 会让 Codex 自己派子代理、层层嵌套，不可控——拆任务。
- `gpt-5.5` 及以上需要 CLI ≥ 0.138；旧 CLI 还会拒绝桌面端写进 `~/.codex/config.toml` 的 `service_tier = "priority"`。升级要**干净重装**：`npm uninstall -g @openai/codex` 再 `npm install -g @openai/codex@latest`（原地升级可能丢平台可选依赖）。
- 廉价机械活 `-Model gpt-5.4-mini` / `gpt-5.3-codex-spark` 够用；别让 Sol 做格式化。
- 给 Codex 传 `-c` 是**合并**语义，排不掉全局 MCP；要隔离用 `CODEX_HOME`（目录须预建）。别碰 `auth.json`。

## 编排者自己的坑（Claude Code 侧）

- 主检出别 `git add -A`：`.codex/` 的草稿与结果自带 gitignore，但其他本地文件（本地 CLAUDE.md、计划）没有。
- Claude Code 的 Bash 工具里写 heredoc 时反斜杠可能减半；Windows PowerShell 5.1 没有 `&&`；工具安全层可能拦下 `cmd /c rmdir`、`gh pr merge`、`git cherry-pick` 之类命令——用 .NET API 或把命令块交给用户执行。
- `gh run watch <id> --exit-status --interval 20` 能在 10 分钟工具超时内等完一次 CI。
- worker 的注释必须走 `$comment-discipline`：不写「Codex / Claude / round 3 / Phase 5」这类过程残留，只写意图、不变量、平台陷阱。
