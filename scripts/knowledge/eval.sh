#!/bin/sh
# Runs the retrieval evaluation with .env.local sourced and flags on.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export HAVEN_KNOWLEDGE_V0_ENABLED=1
export HAVEN_KNOWLEDGE_WRITE_MODE=primary
export HAVEN_KNOWLEDGE_SEARCH_MODE=primary
export HAVEN_EMBEDDING_WAIT_ON_RATE_LIMIT=1
exec "$ROOT/scripts/knowledge/run-with-env.sh" \
    "$ROOT/knowledge/.venv/bin/python" "$ROOT/knowledge/eval/run_eval.py" "$@"
