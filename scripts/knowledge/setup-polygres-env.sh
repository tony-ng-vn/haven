#!/bin/sh
# Creates the haven-knowledge-dev Runtime API key and writes it, with the
# passwordless connection URLs, into the worktree's gitignored .env.local.
# The secret is never echoed; only non-secret metadata is printed.
set -eu
cd "$(dirname "$0")/../.."
umask 077

PROJECT="${POLYGRES_PROJECT:-pa6ee1830f10557dcc9bfd0c}"
OUT=.env.local
trap 'rm -f "$OUT.tmp"' EXIT

polygres --project "$PROJECT" env > "$OUT.tmp"

KEY_JSON=$(polygres --json --project "$PROJECT" keys create haven-knowledge-dev)

SECRET=$(printf '%s' "$KEY_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
def find(o):
    if isinstance(o, dict):
        for k, v in o.items():
            lk = k.lower()
            if lk in ("secret", "api_key", "key", "token", "value") and isinstance(v, str) and len(v) > 10:
                return v
        for v in o.values():
            r = find(v)
            if r:
                return r
    return None
s = find(d)
print(s or "")
')

if [ -z "$SECRET" ]; then
    echo "ERROR: could not locate secret field. Top-level field names were:"
    printf '%s' "$KEY_JSON" | python3 -c 'import json,sys; print(sorted(json.load(sys.stdin).keys()))'
    rm -f "$OUT.tmp"
    exit 1
fi

mv "$OUT.tmp" "$OUT"
ESCAPED=$(printf '%s' "$SECRET" | python3 -c 'import shlex,sys; print(shlex.quote(sys.stdin.read()), end="")')
printf 'export POLYGRES_API_KEY=%s\n' "$ESCAPED" >> "$OUT"
chmod 600 "$OUT"
trap - EXIT

echo "Wrote $OUT. Non-secret key metadata:"
printf '%s' "$KEY_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
def scrub(o):
    if isinstance(o, dict):
        return {k: ("<redacted>" if k.lower() in ("secret", "api_key", "key", "token", "value") else scrub(v)) for k, v in o.items()}
    if isinstance(o, list):
        return [scrub(x) for x in o]
    return o
print(json.dumps(scrub(d), indent=2))
'
