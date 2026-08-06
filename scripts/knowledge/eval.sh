#!/bin/sh
# Runs the retrieval evaluation with .env.local sourced and flags on.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
set -a
. ./.env.local
set +a
export HAVEN_KNOWLEDGE_V0_ENABLED=1
export HAVEN_KNOWLEDGE_WRITE_MODE=primary
export HAVEN_KNOWLEDGE_SEARCH_MODE=primary
cd knowledge/eval
exec ../.venv/bin/python run_eval.py "$@"
