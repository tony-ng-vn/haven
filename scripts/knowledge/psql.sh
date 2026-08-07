#!/bin/sh
# psql against the managed Polygres database using the credentialed URL in the
# worktree .env.local. Usage: psql.sh [--pooled] -c "..." or -f file.sql
set -eu
cd "$(dirname "$0")/../.."
. ./.env.local
URL="$DIRECT_URL"
if [ "${1:-}" = "--pooled" ]; then
    URL="$DATABASE_URL"
    shift
fi
exec psql "$URL" -v ON_ERROR_STOP=1 "$@"
