#!/usr/bin/env bash
# Dispatch a headless Codex line and write a schema-enforced JSON receipt.
#
#   dispatch.sh -m terra -e high -s rw -C <workdir> -o <receipt.json> "<task brief>"
#   dispatch.sh -R <session-id> -o <receipt.json> "<follow-up>"      # resume a line
#
# Requires dangerouslyDisableSandbox at the caller: Codex writes to ~/.codex.
set -euo pipefail

CODEX="/Applications/ChatGPT.app/Contents/Resources/codex"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA="$SKILL_DIR/receipt.schema.json"

MODEL=terra
EFFORT=""
SANDBOX=read-only
WORKDIR="$PWD"
OUT=""
RESUME=""
EPHEMERAL=""
ADD_DIRS=()

# -a is repeatable: every writable root outside -C needs its own -a, or the line
# silently cannot write there and only discovers it mid-run.
while getopts "m:e:s:C:o:R:Ea:" opt; do
  case "$opt" in
    m) MODEL="$OPTARG" ;;
    e) EFFORT="$OPTARG" ;;
    s) [ "$OPTARG" = "rw" ] && SANDBOX=workspace-write || SANDBOX=read-only ;;
    C) WORKDIR="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    R) RESUME="$OPTARG" ;;
    E) EPHEMERAL="--ephemeral" ;;
    a) ADD_DIRS+=(--add-dir "$OPTARG") ;;
    *) echo "usage: dispatch.sh -m sol|terra|luna -e low|medium|high|xhigh -s ro|rw -C dir -o receipt.json [-E] [-a extra-writable-dir]... \"brief\"" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

BRIEF="${1:-}"
[ -n "$BRIEF" ] || { echo "error: task brief required" >&2; exit 2; }
[ -n "$OUT" ]   || { echo "error: -o receipt path required" >&2; exit 2; }

# Hard guard: the top tier makes Codex spawn its own sub-agents, which spawn theirs.
# Unbounded nesting and an unsupervisable run. Split the task instead.
case "$EFFORT" in
  ultra) echo "error: effort 'ultra' is banned (recursive sub-agent spawning). Split the task." >&2; exit 3 ;;
  max)   echo "warn: effort 'max' requires explicit user approval for this run." >&2 ;;
esac

# Default effort follows the model when not given explicitly.
if [ -z "$EFFORT" ]; then
  case "$MODEL" in
    luna)  EFFORT=low ;;
    terra) EFFORT=medium ;;
    sol)   EFFORT=high ;;
  esac
fi

mkdir -p "$(dirname "$OUT")"

if [ -n "$RESUME" ]; then
  exec "$CODEX" exec resume "$RESUME" \
    --output-schema "$SCHEMA" -o "$OUT" \
    "$BRIEF" < /dev/null
fi

exec "$CODEX" exec \
  -m "gpt-5.6-$MODEL" \
  -c model_reasoning_effort="\"$EFFORT\"" \
  -c approval_policy='"never"' \
  -s "$SANDBOX" \
  -C "$WORKDIR" \
  ${ADD_DIRS[@]+"${ADD_DIRS[@]}"} \
  $EPHEMERAL \
  --output-schema "$SCHEMA" \
  -o "$OUT" \
  "$BRIEF" < /dev/null
