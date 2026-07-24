# claude-skills

Private orchestration skills for Claude Code.

Claude is the decision layer; Codex is the execution layer. These skills keep that
boundary enforceable rather than aspirational.

## skills/codex-dispatch

Dispatches headless Codex lines (`gpt-5.6-sol` / `-terra` / `-luna`) as subagents and
consumes schema-enforced JSON receipts, so a run costing tens of thousands of Codex
tokens returns to Claude as roughly two hundred.

Three things are enforced in code rather than prose:

- `receipt.schema.json` forces every discovered issue into `blocker` / `follow-up` /
  `out-of-scope`, with a mandatory `reproduced` boolean. An unreproduced finding cannot
  be a blocker.
- `dispatch.sh` hard-blocks reasoning effort `ultra`, which makes Codex spawn its own
  sub-agents recursively.
- `next_decision` is capped at two entries, each requiring options and a recommendation.

## Install

Symlink or copy into a project's `.claude/skills/`, or into `~/.claude/skills/` for all
projects. Keep this repository as the source of truth.

    ln -s ~/Documents/claude-skills/skills/codex-dispatch <project>/.claude/skills/codex-dispatch
