#!/bin/sh
# Runs the knowledge test suite with .env.local sourced.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
set -a
. ./.env.local
set +a
cd knowledge
exec ./.venv/bin/python -m pytest "$@"
