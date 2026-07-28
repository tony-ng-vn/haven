#!/usr/bin/env bash
# Wraps a CI command with /usr/bin/time -l (BSD time, ships with macOS) and
# appends wall time + peak RSS to the job summary. Only means anything on the
# self-hosted runner, where the hardware isn't a known fixed quantity like
# ubuntu-latest/macos-latest.
set -o pipefail

label="$1"
shift

log="$(mktemp)"
{ /usr/bin/time -l "$@"; } 2>&1 | tee "$log"
status="${PIPESTATUS[0]}"

real="$(grep -E '^ *[0-9.]+ real' "$log" | tail -1 | awk '{print $1}')"
rss_bytes="$(grep 'maximum resident set size' "$log" | tail -1 | awk '{print $1}')"
rss_mb="${rss_bytes:+$((rss_bytes / 1024 / 1024))}"

{
  echo "### ${label}"
  echo "| metric | value |"
  echo "|---|---|"
  echo "| wall time (s) | ${real:-n/a} |"
  echo "| peak RSS (MB) | ${rss_mb:-n/a} |"
} >> "$GITHUB_STEP_SUMMARY"

rm -f "$log"
exit "$status"
