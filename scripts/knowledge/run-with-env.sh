#!/bin/sh
# Sources the worktree .env.local (secrets stay out of the transcript) and
# executes the given command with that environment.
set -eu
cd "$(dirname "$0")/../.."
if [ ! -f ./.env.local ]; then
    echo "ERROR: .env.local is missing; run scripts/knowledge/setup-polygres-env.sh first." >&2
    exit 1
fi
set -a
. ./.env.local
set +a
exec "$@"
