#!/usr/bin/env bash
#
# graph/scripts/update_app.sh
#
# usage: ./scripts/update_app.sh
#
# The one-command version of "rebuild, replace /Applications/Your Sky.app, relaunch",
# which is the update loop for this tool (see SIGNING.md, "The update loop": there is no
# in-app or network updater, and none is planned).
#
# Steps, in order:
#   1. Quit a running "Your Sky" instance, if one is running. Never launches the app just
#      to quit it.
#   2. Regenerate the Xcode project (xcodegen generate), then build Release to a SCRATCH
#      DerivedData location, never straight into /Applications: a failed build must never
#      leave the owner without a working app.
#   3. Only on a successful build, replace /Applications/Your Sky.app with the freshly
#      built copy and relaunch it.
#   4. Report whether the installed build is ad-hoc or carries a real signing identity
#      (via codesign -dv), with a one-line reminder that ad-hoc means Full Disk Access
#      will need to be re-granted (see SIGNING.md for the actual fix).
#
# On any build failure, this script exits non-zero and does not touch the installed app
# at all. Never invokes sudo, never modifies the keychain, System Settings, or TCC state
# in any way -- those are exactly the things this script does NOT do.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/App"
SCHEME="ConnectionGraph"
APP_NAME="Your Sky"
INSTALL_PATH="/Applications/$APP_NAME.app"

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/your-sky-build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "==> Checking for a running $APP_NAME instance"
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "==> Quitting the running $APP_NAME instance"
    # tell application "X" to quit would LAUNCH "X" if it were not already running, which
    # is exactly what the pgrep guard above prevents: this only ever runs against a
    # process we already confirmed is alive.
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        sleep 1
    done
    # Fallback if the graceful Apple Event quit did not land in time. SIGTERM (pkill's
    # default), not SIGKILL: still a normal terminate request, not a forced kill.
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

echo "==> Regenerating the Xcode project"
(cd "$APP_DIR" && xcodegen generate)

echo "==> Building Release to a scratch location (installed app is untouched until this succeeds)"
if ! xcodebuild \
    -project "$APP_DIR/ConnectionGraph.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build; then
    echo "error: build failed -- $INSTALL_PATH was NOT touched" >&2
    exit 1
fi

BUILT_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "error: build reported success but no app bundle was found at:" >&2
    echo "  $BUILT_APP" >&2
    echo "$INSTALL_PATH was NOT touched" >&2
    exit 1
fi

echo "==> Installing to $INSTALL_PATH"
rm -rf "$INSTALL_PATH"
cp -R "$BUILT_APP" "$INSTALL_PATH"

echo "==> Relaunching"
open -n "$INSTALL_PATH"

echo "==> Checking the installed signature"
CODESIGN_OUTPUT="$(codesign -dv "$INSTALL_PATH" 2>&1 || true)"
# Signature= and TeamIdentifier= are printed by codesign -dv, but which lines are present
# (and what they say) differs between an ad-hoc build and a real identity, so each is only
# shown here if codesign actually produced it, never a blank placeholder.
DETAIL_LINES="$(echo "$CODESIGN_OUTPUT" | grep -E '^(Signature=|TeamIdentifier=)' || true)"

if echo "$CODESIGN_OUTPUT" | grep -q 'flags=.*adhoc'; then
    echo "==> Done. Signing: ad-hoc"
    echo "$DETAIL_LINES" | sed 's/^/    /'
    echo "warning: ad-hoc signed -- Full Disk Access will need to be re-granted for this build. See SIGNING.md."
else
    echo "==> Done. Signing: identity present"
    echo "$DETAIL_LINES" | sed 's/^/    /'
fi
