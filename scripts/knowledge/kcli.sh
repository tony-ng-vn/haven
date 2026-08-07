#!/bin/sh
# Runs the haven_knowledge CLI with .env.local sourced and dev flags on.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export HAVEN_KNOWLEDGE_V0_ENABLED=1
export HAVEN_KNOWLEDGE_WRITE_MODE=primary
export HAVEN_KNOWLEDGE_SEARCH_MODE=primary
exec "$ROOT/scripts/knowledge/run-with-env.sh" \
    "$ROOT/knowledge/.venv/bin/python" -m haven_knowledge.cli "$@"
