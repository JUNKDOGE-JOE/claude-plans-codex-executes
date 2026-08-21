---
name: comment-discipline
description: Comment-writing discipline for any code repository. Use before writing, editing, reviewing, or cleaning source-code comments in Rust, Python, JavaScript/TypeScript, JSX/ExtendScript templates, shaders, tests, and bridge code, especially when touching platform-specific behavior, safety boundaries, protocol adapters, or regression tests.
---

# Comment Discipline

## Overview

Keep comments rare, durable, and useful. Comments should explain intent, platform traps, invariants, and safety boundaries; they should not record the AI/review/process trail that produced the code.

## Before Adding A Comment

Prefer clearer names, tighter helper extraction, typed arguments, or a focused test name before adding a comment. Add a source-code comment only when deleting it would make the code meaningfully harder to maintain six months later.

Use comments for:

- Non-obvious intent or tradeoff.
- Subtle invariant, contract, ordering requirement, or timeout/safety boundary.
- Host-application, OS, GPU/driver, wire-protocol, or backend behavior that code cannot make obvious.
- Regression-test rationale when the test would otherwise look arbitrary.
- Template contracts: placeholders, generated output shape, or "never throws" behavior.

Do not comment routine control flow, obvious assignments, or section labels that merely repeat function names.

## Forbidden Comment Content

Do not add comments that mainly encode project-process metadata:

- AI or reviewer provenance: "GPT suggested", "Codex", "Claude", "review round", "PR review".
- Phase, task, batch, or polish labels: "Phase 5", "P4.a", "round 3", "fix batch".
- Date stamps or author signatures as the reason a behavior exists.
- Archaeology: "old code used X", "changed from Y", "mirrors deletion", "legacy cleanup".
- TODO/FIXME/HACK/XXX without a stable issue and a short present-tense problem statement.
- A bare issue/spec/design-doc reference that forces the reader to leave the code to understand why.

If history matters, put it in the commit message or PR. If future work matters, file an issue or backlog item. If design rationale is too large for a local comment, summarize the local invariant in code and keep the long form in docs (for repositories with ADRs, name the ADR after the self-contained explanation, never instead of it).

## References As Supporting Evidence Only

Allow a stable issue number, ADR id, or date only as supporting evidence after the comment is already self-contained. The reader must understand the reason without following the reference.

Good:

```py
# Keep traversal wall-clock bounded so large projects return partial results
# instead of hitting the evalScript timeout with empty output.
```

Acceptable when useful:

```py
# Keep traversal wall-clock bounded so large projects return partial results
# instead of hitting the evalScript timeout with empty output. Regression: #12.
```

Avoid:

```py
# #12: traversal must be bounded.
```

Allow time-versioned notes only for facts that genuinely vary by upstream version or live-probed host/backend behavior. Prefer naming the upstream version or protocol over a date when possible.

Do not clean or judge comments in generated, vendored, or dependency code (`dist/`, `node_modules/`, `target/`, vendored SDK headers, third-party single-file libraries). Treat bridge, template, and regression-test code as comment-heavy by necessity; keep comments there if they explain fragile behavior, not line-by-line mechanics.

## Rewrite Patterns

When editing comments, preserve the useful invariant and remove process residue.

```js
// Bad: verified in round 2, PR #14 review said the permission type is weird.
// Good: Match permission-like SSE events defensively because the backend does
// not emit this path for read-only tools during acceptance.
```

```py
# Bad: Phase B checkpoint fix.
# Good: Auto-checkpoint failure must never abort the user's edit; degrade to a
# checkpointSkipped note instead.
```

```jsx
// Bad: TODO later optimize this scan.
// Good: Stop scanning after the budget so large projects return partial results
// instead of freezing the bridge.
```

## Quick Audit

Before finishing a change that adds or edits comments, run a targeted source-only scan when practical (adjust the globs to the repository's languages and exclude generated/vendored trees):

```bash
rg -n "(GPT|Codex|Claude|Gemini|review|round [0-9]+|Phase [0-9A-G]|TODO|FIXME|HACK|XXX|FUTURE-WORK|changed from|old code|deprecated)" \
  -g "*.rs" -g "*.py" -g "*.js" -g "*.ts" -g "*.jsx" -g "*.mjs" -g "*.glsl" \
  -g "!**/dist/**" -g "!**/node_modules/**" -g "!**/target/**"
```

Inspect matches; do not blindly delete. Keep comments that explain a real runtime constraint or test invariant after removing stale process metadata.
