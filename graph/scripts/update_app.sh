#!/usr/bin/env bash
#
# graph/scripts/update_app.sh
#
# usage: ./scripts/update_app.sh [--allow-stale]
#
# The one-command version of "rebuild, replace /Applications/Your Sky.app, relaunch",
# which is the update loop for this tool (see SIGNING.md, "The update loop": there is no
# in-app or network updater, and none is planned).
#
# Steps, in order:
#   1. Check this checkout against origin/graph-main. If it is behind, refuse to install
#      (this exact mistake has regressed the owner's installed app twice: installing a
#      build made from a branch that had not picked up a fix landed on graph-main since).
#      --allow-stale overrides this for a deliberate "try my WIP branch" install.
#   2. Quit a running "Your Sky" instance, if one is running. Never launches the app just
#      to quit it.
#   3. Regenerate the Xcode project (xcodegen generate), then build Release to a SCRATCH
#      DerivedData location, never straight into /Applications: a failed build must never
#      leave the owner without a working app.
#   4. Check the FRESH build's signature. If it is ad-hoc, print a clear reminder -- BEFORE
#      touching the installed app -- that this install will cost the current Full Disk
#      Access grant (ad-hoc signing means every rebuild is a new app to TCC; see
#      SIGNING.md), so an unnecessary reinstall is an informed choice, not a surprise.
#   5. Only on a successful build, replace /Applications/Your Sky.app with the freshly
#      built copy and relaunch it.
#   6. Report whether the installed build is ad-hoc or carries a real signing identity.
#
# On any build failure, or a refused stale checkout, this script exits non-zero and does
# not touch the installed app at all. Never invokes sudo, never modifies the keychain,
# System Settings, or TCC state in any way -- those are exactly the things this script
# does NOT do.

set -euo pipefail

ALLOW_STALE=0
if [ "${1:-}" = "--allow-stale" ]; then
    ALLOW_STALE=1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/App"
SCHEME="ConnectionGraph"
APP_NAME="Your Sky"
INSTALL_PATH="/Applications/$APP_NAME.app"

echo "==> Checking this checkout against origin/graph-main"
if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "warning: $REPO_ROOT is not a git checkout -- cannot verify it is current. Proceeding." >&2
elif ! git -C "$REPO_ROOT" fetch origin graph-main --quiet 2>/dev/null; then
    echo "warning: could not fetch origin/graph-main (offline?) -- cannot verify this checkout is current. Proceeding." >&2
else
    CURRENT_BRANCH="$(git -C "$REPO_ROOT" symbolic-ref --short -q HEAD || echo "(detached HEAD)")"
    BEHIND_COUNT="$(git -C "$REPO_ROOT" rev-list --count HEAD..origin/graph-main 2>/dev/null || echo 0)"
    if [ "$BEHIND_COUNT" -gt 0 ]; then
        echo "warning: this checkout (branch '$CURRENT_BRANCH') is $BEHIND_COUNT commit(s) behind origin/graph-main." >&2
        echo "warning: installing this build would regress any fix that landed on graph-main since this branch diverged." >&2
        if [ "$ALLOW_STALE" -eq 1 ]; then
            echo "==> --allow-stale given: installing anyway."
        else
            echo "error: refusing to install a stale build. Pull origin/graph-main first, or pass --allow-stale to override." >&2
            exit 1
        fi
    else
        echo "==> Checkout '$CURRENT_BRANCH' is current with origin/graph-main."
    fi
fi

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

# Checked on the FRESH build, before it ever touches /Applications: signing status is a
# property of this build's own bytes, not of the previously installed copy, and the whole
# point of warning here is to inform the decision to swap at all, not to report on it
# afterward.
CODESIGN_OUTPUT="$(codesign -dv "$BUILT_APP" 2>&1 || true)"
IS_ADHOC=0
if echo "$CODESIGN_OUTPUT" | grep -q 'flags=.*adhoc'; then
    IS_ADHOC=1
fi

if [ "$IS_ADHOC" -eq 1 ]; then
    echo "warning: this build is ad-hoc signed. Installing it will invalidate the current"
    echo "warning: Full Disk Access grant (ad-hoc signing means every rebuild is a new app"
    echo "warning: to macOS TCC) -- see SIGNING.md for how to stop this from happening."
fi

echo "==> Installing to $INSTALL_PATH"
rm -rf "$INSTALL_PATH"
cp -R "$BUILT_APP" "$INSTALL_PATH"

echo "==> Relaunching"
open -n "$INSTALL_PATH"

# Signature= and TeamIdentifier= are printed by codesign -dv, but which lines are present
# (and what they say) differs between an ad-hoc build and a real identity, so each is only
# shown here if codesign actually produced it, never a blank placeholder.
DETAIL_LINES="$(echo "$CODESIGN_OUTPUT" | grep -E '^(Signature=|TeamIdentifier=)' || true)"

if [ "$IS_ADHOC" -eq 1 ]; then
    echo "==> Done. Signing: ad-hoc"
    echo "$DETAIL_LINES" | sed 's/^/    /'
    echo "warning: ad-hoc signed -- Full Disk Access will need to be re-granted for this build. See SIGNING.md."
else
    echo "==> Done. Signing: identity present"
    echo "$DETAIL_LINES" | sed 's/^/    /'
fi
