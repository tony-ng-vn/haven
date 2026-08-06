#!/bin/sh
# Sources the worktree .env.local (secrets stay out of the transcript) and
# executes the given command with that environment.
set -eu
cd "$(dirname "$0")/../.."
set -a
. ./.env.local
set +a
exec "$@"
