#!/bin/sh
# Grab the booted simulator's screen into ios/.screens/ so the remote session
# can read it. Run from the Mac: ./ios/shot.sh [label]
#
# .screens/ is git-ignored and synced back to the server by Mutagen.
set -eu

dir="$(cd "$(dirname "$0")" && pwd)/.screens"
mkdir -p "$dir"

label="${1:-shot}"
out="$dir/$(date +%H%M%S)-$label.png"

xcrun simctl io booted screenshot "$out"
echo "$out"
