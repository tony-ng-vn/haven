# Why Full Disk Access asks again after every rebuild, and how to stop it

This is a plain explanation of one specific annoyance: granting Your Sky access in
System Settings, rebuilding the app, and finding Full Disk Access blocked again even
though the toggle in System Settings still shows on.
It also covers the fix, which is the owner's own action in Keychain Access or Xcode,
plus the small amount of build configuration that makes the fix take effect.

## The actual cause

Your Sky is currently ad-hoc signed.
That means the build has no code-signing certificate at all: `CODE_SIGN_IDENTITY` is set
to `-`, which tells Xcode "sign with whatever placeholder identity is needed to run
locally, nothing more."

macOS's privacy system (TCC, the thing that tracks Full Disk Access, Contacts, and similar
grants) needs a stable way to recognize "this is the same app as before."
For a properly signed app, TCC keys the grant on the app's designated requirement, which
boils down to its bundle identifier plus its signing certificate.
Both of those stay the same across rebuilds, so the grant survives.

An ad-hoc signed app has no certificate, so TCC falls back to keying the grant on the
binary's cdhash, a hash of the compiled executable itself.
Every rebuild changes the compiled bytes, so the cdhash changes, so TCC sees a different
app and drops the grant, even though the bundle identifier, the app name, and the icon are
all identical to the copy that was granted a minute ago.
This is true no matter how the rebuild happened: recompiling one line of Swift, swapping
in a newer copy of the same code, or reinstalling to `/Applications` all produce a new
cdhash.

The fix is not a workaround inside the app.
It is giving the build a real, stable signing identity, so TCC has a designated
requirement to key on instead of a cdhash.

## Two ways to get a stable identity

Either of these works.
Pick whichever is less friction; there is no functional difference for a single-machine,
never-distributed tool like this one.

### Option A: a self-signed certificate in Keychain Access

This does not require an Apple ID or any Apple account at all.

1. Open Keychain Access (in Applications > Utilities).
2. From the menu bar, choose Keychain Access > Certificate Assistant > Create a Certificate.
3. Give it a name you will recognize later, for example `Your Sky Local Signing`.
4. Set Identity Type to "Self Signed Root".
5. Set Certificate Type to "Code Signing".
6. Leave "Let me override defaults" unchecked unless you have a specific reason to change
   the validity period or key size.
7. Click Create, then Continue/Done through the remaining screens.

The certificate now exists in your login keychain, trusted by your own machine, for your
own machine's use.
Nothing about this step is scripted anywhere in this repository, on purpose: creating a
certificate and touching the keychain are the owner's own action in the owner's own UI.
No script here does this for you, and none should.

### Option B: a free Apple ID identity via Xcode

This uses an ordinary Apple ID, no paid developer program required.

1. Open Xcode > Settings (or Preferences) > Accounts.
2. Click the `+` button and add your Apple ID if it is not already listed.
3. Xcode will provision a free personal team for that Apple ID, visible in the same
   Accounts pane once added.
4. Note the Team ID shown there; you will need it below.

## Pointing the build at the identity

The build's signing settings live in `App/Signing.xcconfig`, which defaults to ad-hoc
signing so a fresh checkout on a machine with no identity always builds successfully.
To use a real identity, create `App/Signing.local.xcconfig` (a new file, not tracked by
git: see `.gitignore`) with the settings for whichever option you picked.

For a self-signed certificate (Option A), Manual signing, no team:

```
CODE_SIGN_IDENTITY = Your Sky Local Signing
```

Use the exact name you gave the certificate in step 3 above.

For a free Apple ID identity (Option B), Automatic signing, with your team:

```
CODE_SIGN_STYLE = Automatic
DEVELOPMENT_TEAM = ABCDE12345
```

Replace `ABCDE12345` with the Team ID from Xcode's Accounts pane.

After creating or editing `App/Signing.local.xcconfig`, regenerate the Xcode project and
rebuild:

```
cd graph/App && xcodegen generate
```

Then build Release normally (via Xcode, `xcodebuild`, or `graph/scripts/update_app.sh`,
see below).
`update_app.sh` prints whether the resulting build is ad-hoc or signed, so you can confirm
the identity actually took effect without needing to run `codesign` by hand.

## The one-time re-grant

The very first build made with a real identity will still need Full Disk Access granted
once, the same as any brand-new app.
That is expected, not a sign that anything is wrong.

Every build made with that same identity from then on keeps the grant, because the
designated requirement TCC is keying on (bundle id plus certificate) no longer changes
between builds.
Only actions that change the identity itself would need a fresh grant again: switching
between Option A and Option B, regenerating the self-signed certificate, or moving to a
different Apple ID team.

## What this does NOT solve

A self-signed or free-Apple-ID-signed app is still not notarized.
Notarization requires a paid Apple Developer Program membership and submitting builds to
Apple, neither of which this repository does or should do: `graph/GOAL.md` explicitly
rules out distribution and notarization work, because this is a personal, single-user
tool that never leaves the owner's own machine.

Concretely, this means:

- The app is not, and will not become, installable or runnable on anyone else's Mac
  without that person separately bypassing Gatekeeper themselves.
- Nothing here makes the app "shippable" in any wider sense.
- The scope of this fix is exactly the owner's own re-grant annoyance on the owner's own
  machine, nothing more.

## The update loop

`graph/scripts/update_app.sh` is the one-command version of rebuild, replace
`/Applications/Your Sky.app`, and relaunch.
It is the update mechanism for this tool: there is no in-app "check for update" feature,
and none is planned.

`graph/GOAL.md` constraint 4 rules out any server component, and this is a tool the owner
builds themselves from source they already have on disk, so a network-based updater would
be solving a problem that does not exist here.
Running `update_app.sh` after pulling new code is the update button.
