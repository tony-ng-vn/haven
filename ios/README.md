# Haven iOS (Phase 0 foundations)

This is the native SwiftUI client scaffold for Haven.
Its only job in Phase 0 is to prove the riskiest seam in the whole native plan: Clerk sign-in on iOS authenticating a real Convex query.

See `../mvp-design.md` for the full plan. Phase 0's strict definition of done is: sign in with Clerk on a physical iPhone, call an authenticated Convex query, and see a live result.

## Status

The scaffold is written against the pinned SDK versions and mirrors the `clerk-convex-swift` package's own example app, so the integration pattern is verified.
What a green build proves and does not prove:

- A green simulator build proves the code compiles against the real SDKs and the Swift packages resolve and link.
- It does NOT prove authentication works, because nothing executes during a build.

Finishing the Phase 0 DoD is a human step: add the two config values, create the Clerk JWT template, and run on a device (below).

## Prerequisites

- Xcode 26.x with an installed iOS simulator runtime (open Xcode once, or run `xcodebuild -downloadPlatform iOS`).
- XcodeGen: `brew install xcodegen`.

## Generate and open

The `.xcodeproj` is generated from `project.yml` and is git-ignored.

```sh
cd ios
xcodegen generate
open Haven.xcodeproj
```

## Configure

**Nothing, for a simulator build.** `Haven/Config.swift` already carries both
Clerk keys and both Convex urls, split by build configuration, and a debug build
takes the development side of that split on its own:

| A debug build talks to | |
|---|---|
| Clerk | the `valued-bonefish-64` development instance |
| Convex | `brilliant-puma-925`, the development deployment |

So nothing you do in the simulator can reach production data, and the production
Clerk instance is not exercised at all -- a debug build cannot tell you whether
the production sign-in works. That is a web check (`inhavens.com/sign-in`) or a
release build, not this.

The three steps below are one-time setup for the *development* deployment, and
they have already been done for this project. They are kept because a new
deployment needs them:

1. In the Clerk dashboard, create a JWT template named `convex` (the Convex integration template).
2. On the Convex deployment, set `CLERK_JWT_ISSUER_DOMAIN` to the Clerk Frontend API URL: `npx convex env set CLERK_JWT_ISSUER_DOMAIN <domain>`.
   This is already read by `convex/auth.config.ts`, which pins `applicationID: "convex"`.
3. Nothing in `Config.swift`. Editing it to point a debug build at production is
   not a shortcut for testing the production swap -- it writes real rows from a
   development build, and the values are asserted by `ConfigTests`.

## Run

Build to a simulator or a device.

**Pick an iPhone.** Haven declares `TARGETED_DEVICE_FAMILY: "1"` and portrait
only, so an iPad destination will not install -- that is deliberate (there is no
adaptive layout), not a broken build.
Signed out, you get the welcome screen, which owns sign-in.
Signed in, the app reads `profiles:getMyCard` (auth-gated by `requireUser`) and shows the first question that card has not answered, or `HavenTabs` once there are none left.

That read is also the Phase 0 proof, and it fails loudly rather than quietly: a card the app cannot read stops the flow on "Haven could not load your card" with a Try again button.
If that is what you see straight after signing in, Clerk minted a token and Convex rejected it -- check the `convex` JWT template and `CLERK_JWT_ISSUER_DOMAIN`.

To start the questions again, empty the `profiles` table on the dev deployment and reinstall the app: `xcrun simctl uninstall booted com.inhavens.haven`.

### Signing for a physical device

`xcodegen generate` rewrites the project, so a signing team set by hand in Xcode is wiped on each regenerate.
Either set your team once in Signing & Capabilities after generating, or add `DEVELOPMENT_TEAM` to `project.yml`.

## Build and run from the command line

Always run `xcodegen generate` first.
The `.xcodeproj` is git-ignored, so a copy left over from an earlier checkout can be missing files that exist on disk, and the build then fails for a reason that is not real.

```sh
xcodegen generate
# Use any installed simulator (xcrun simctl list devices); iPhone 17 ships with the iOS 26.5 runtime.
xcodebuild build -project Haven.xcodeproj -scheme Haven \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build
```

Never add `CODE_SIGNING_ALLOWED=NO` to a command you run on your own machine, whichever command it is.
It produces an app that crashes on every launch, and the crash report blames `Clerk.swift` rather than the real cause.

The reason is worth knowing, because the entitlement the simulator reads is not the one you would expect.
For a simulator build Xcode writes two files: `Haven.app.xcent`, the real code-signing entitlements, which is empty here because there is no signing team, and `Haven.app-Simulated.xcent`, which carries `application-identifier` and `keychain-access-groups` under a placeholder `FAKETEAMID`.
Only the second one matters, and it is embedded as a `__TEXT,__entitlements` section in the binary rather than into the signature.
That is why `codesign -d --entitlements` prints an empty dict on a build that works perfectly.

`CODE_SIGNING_ALLOWED=NO` skips the step that produces and embeds it, leaving a `linker-signed` binary with no such section.
Clerk then fails on `OSStatus -34018: A required entitlement isn't present` inside `Clerk.configure`, which runs from a `.task` behind `LaunchGate`'s first frame -- so the night background paints, then the crash happens a beat later, rather than nothing appearing at all.

`-derivedDataPath build` puts the app somewhere you can name (`build/` is git-ignored).
To install and launch it on the booted simulator:

```sh
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Haven.app
xcrun simctl launch --console-pty booted com.inhavens.haven
```

`--console-pty` keeps the app's stdout and stderr in the terminal, which is where a Swift trap prints the message the crash report leaves out.

## Tests

```sh
xcodegen generate
xcodebuild test -project Haven.xcodeproj -scheme Haven \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Swift Testing, in the `HavenTests` target.

No `CODE_SIGNING_ALLOWED=NO` here either, and this is the case that surprises people.
The tests would pass with it: they are hosted in the app, and under XCTest Clerk skips the keychain work that would otherwise throw, so the run gets through `Clerk.configure` where a real launch traps.
What it costs you is the simulator. A hosted test run installs the app, so an unsigned run replaces whatever is on the device with a build that crashes the moment you tap its icon, and stays that way until something reinstalls a good one.
That is a confusing bug to chase an hour later, and skipping the signing step buys nothing.

CI keeps the flag in `.github/workflows/ios.yml`, which is fine: nobody opens the app on a runner.

CI runs these tests in `.github/workflows/ios.yml`, on any pull request that touches `ios/`.
A pull request that touches no Swift skips the job, because macOS runners are billed at several times the Linux rate.

What is worth testing here: pure logic. Sky generation, search filtering, the pending queue, overlay merge.
Springs and haptics are judged by hand on a device, because no assertion captures whether something feels right.

Verified: this scaffold builds green against ConvexMobile 0.8.1, ClerkKit/ClerkKitUI 1.3.3, and ClerkConvex 0.1.0 on the iOS 26.5 simulator.

## Design system

Everything in `Haven/Design` is milestone 2 of `../phase1-build-plan.md`, and everything downstream imports its vocabulary rather than inventing its own.

- `HavenColor` is the committed dusk palette. The list is closed: a surface that seems to need a new hue almost always needs an existing one at a different opacity.
- `HavenFont` holds the type rules as view modifiers, not raw fonts, for one reason: it keeps `.serif` inside that one file. Serif (New York) is reserved for people's names via `personName(_:)`, and everything else is SF Pro. A grep for "serif" anywhere else in `Haven/` should return nothing. Every style is built from a relative text style, so Dynamic Type scales all of it.
- `HavenMotion` holds the durations and the strong ease-out. Use `havenAnimation(_:value:)` instead of `.animation(_:value:)` and Reduce Motion is handled for you: the state change still happens, it just arrives instantly.
- `NightBackground` and `DustLayer` are the atmosphere. Neither ever responds to progress.
- `SkyView` renders a `Sky` from `SkyGenerator`. Each figure star has its own brightness, from 0 for the unlit faint dot to 1 for fully lit. Everything attached to a star fades with it: an edge is drawn at the dimmer of its two stars, and a diffraction flare at its own star's, because both are signatures of brightness and neither can honestly outshine the star it comes from. The two-state figure is the `litMajors` initialiser, which is just intensities of 0 and 1. Brightness is a plain input: `SkyView` knows nothing about ignition order, and animating it is the caller's job.
- `HavenCard` is a person's card as one component -- figure, serif name, optional inline photo, city line, primary contact chip -- shared by the reveal and My Card, because a card that drifted between the two would stop reading as an identity. Empty fields render nothing; the unlit star is the nudge.
- `StarSlot` fixes which figure star each profile field owns. Do not make it dynamic; the edit screen's unlit stars are only legible because a field's star never moves.
- `HavenScreen`, `HavenField`, `PrimaryButton`, `GhostButton` and `HavenRow` are the shared controls.
- `havenDismissable()` puts the top-right close control on a sheet, on top of -- not instead of -- swipe-to-dismiss. Every `.sheet` in Haven carries it, except the two that already come with their own: Clerk's `AuthView` and `SafariPage`'s `SFSafariViewController` (the legal pages and the contact question's Composio browser trip both use it).
- `HavenScreen`'s `contentAlignment` is not cosmetic. Content that never changes height is centred; content that grows, such as a suggestion list or a panel that opens, is top-aligned, or answering the question moves the field out from under the person's finger. The figure follows: it takes the gap above centred content and the gap below top-aligned content, and disappears when neither is big enough to read as a figure.

Every surface also has SwiftUI previews covering the default size, an accessibility text size, and the Reduce Motion path.
SwiftUI's own `accessibilityReduceMotion` is read-only, so the previews flip it with `havenReduceMotion()` instead.
Compiling and passing tests says nothing about whether something looks right, so every screen is judged by eye before it is called done.

## Onboarding

`Haven/Onboarding` is milestone 4 of `../phase1-build-plan.md`, built one question at a time.

- `WelcomeScreen` is screen 0 and owns sign-in.
- `OnboardingFlow` owns everything after it: one `OnboardingModel`, so the sky and the answers so far survive every question.
- `OnboardingModel` decides which question is on screen from the card that `profiles:getMyCard` returns, never from a counter. A counter is lost on reinstall and lies after an edit made on another device.
- The constellation is seeded from the Clerk user id. Names collide and change, and the profile row does not exist yet on the first question, where the figure is already on screen.
- A commit publishes the new card first and the next question a beat later, so the star the person just lit is actually on screen before the next question replaces it.
- Skipping is remembered on the device, not on the card. The server has no field for "asked and declined", and adding one would make a skipped city indistinguishable from one nobody has got round to asking for. The store is keyed by user, so a second account on the same phone starts clean.
- `CityCompleter` wraps `MKLocalSearchCompleter` for the typeahead and resolves the chosen completion with `MKLocalSearch`, because a completion is two display strings while the card stores a real locality, admin area and country. A city MapKit does not know is still accepted as typed text; being unknown to MapKit is not a reason to be told to skip the question.
- The contact question's two groups are a fact about the platforms, not a layout choice. X, LinkedIn and Instagram authorize, all three through Composio; phone is supplied by hand.
- Every proven handle comes from Composio's own profile tool (`convex/composio.ts`), not from whatever a payload happened to carry: `LINKEDIN_GET_MY_INFO`'s `vanityName`, `INSTAGRAM_GET_USER_INFO`'s `username`, and X's `username` are all extracted server-side and stored `verified`. LinkedIn's confirm panel used to always open, back when Clerk's payload could carry a username that was not the profile address; now every connected outcome is proven the same way, so the panel only opens when an authorization fails.
- Every connectable row has somewhere to land when the authorization fails, is declined, or -- Instagram only -- proves an account Composio's tool cannot read. A platform that will not connect is a reason to ask, never a dead end, so X, LinkedIn and Instagram all degrade to the same typed panel.
- `ContactValue` holds the per-platform parsing and is where it is tested; `ContactEntry.parse` is the one place a typed or confirmed value becomes a contact, and it is never `verified`, because a value that had to be typed was by definition not proven by the platform.
- Instagram authorizes like the other two, but Composio's `INSTAGRAM_GET_USER_INFO` only reads creator and business accounts -- a personal account authorizes fine and then fails to prove a handle. The row names that limit before the tap (`ContactPlatform.subtitle`) and `completeSocialConnection`'s `unsupported_account` status names it again in the fallback panel's failure copy (`ContactPlatform.unsupportedReason`), so neither reads as Haven's own restriction.
- `ContactConnector.initiate` calls `composio:initiateSocialConnection`, which returns a redirect URL and a connected-account id, or short-circuits straight to a handle when Composio's own connected-accounts list already has an active one for that toolkit -- the dedupe lives on the backend, not in a Clerk user reload. `ContactScreen` opens the redirect in `SafariPage` and hands the connected-account id to `ContactConnector.poll`, which calls `composio:completeSocialConnection` every two seconds until it hears back or its own 120-second deadline passes. That deadline is the loop's own, not `Task.value(within:)`'s: `Task.value(within:)` abandons a task that never finishes rather than cancelling it, so relying on it here would leave the loop polling in the background forever once the bound hit. Dismissing the browser by hand cancels the polling task immediately instead of waiting for either deadline.
- Nothing on this screen dead-ends. An authorization that fails opens the same fallback panel, and Skip is held while a round trip is out, or the answer would land on a screen nobody is looking at.
- A connected account still imports its profile photo, the same as it did through Clerk. `completeSocialConnection`'s `connected` response carries an optional `photoUrl` -- present for LinkedIn and Instagram, not proven live for X -- which `ContactScreen.finish` hands to `OnboardingModel.rememberAvatar` and `saveContact` imports once the contact answer itself has landed, via `profiles:generateUploadUrl` and `updateMyProfile`. `AvatarImport.shouldReplace` is the one rule this checks and the one piece of it testable without a network: never overwrite a photo somebody already chose.

Built so far: screens 0 to 3 (welcome, name, location, contact). The card reveal is next; until it exists, a person through the questions goes straight on to `HavenTabs`.

## The app after onboarding

`HavenTabs` is the shell: People and Search as two tabs, with the card reachable from the People screen's toolbar, and the Lock Screen explainer presented as a sheet from People.
Two tabs rather than one screen whose search field expands, per `../phase1-build-plan.md`'s open question 3.

`Haven/Model` holds types that are nobody's screen. `MyCard` lives there because the reveal, the edit screen and the card's back all read it, and a type three surfaces import should not live inside one of them.

`DirectoryScreen`, `SearchScreen`, `MyCardScreen` and `LockScreenExplainer` exist as placeholders so the routes between them are real and compiled while each screen is built.
Each says plainly that it is not built yet rather than dressing up as finished.

The card turns over on a tap to show its back: a QR pointing at the public web card page, `inhavens.com/<handle>`.
There is no separate beacon screen and no toolbar button for it, because the code and the card were the same object described twice.
A debug build points at the dev deployment, which nothing on the web reads, so a code made there resolves to nobody -- expected rather than broken, and argued out on `BeaconAddress`.

Not yet built, and named here so it is a decision rather than a gap:

- Brand glyphs on the contact rows. The rows are text only; the marks are third-party trademarks with their own usage rules, and picking them is its own piece of work.

## Architecture notes

- Dependencies (SPM, pinned in `project.yml`): `ConvexMobile` (convex-swift), `ClerkKit` + `ClerkKitUI` (clerk-ios), `ClerkConvex` (clerk-convex-swift).
- `convex` is a single app-lifetime `ConvexClientWithAuth` using `ClerkConvexAuthProvider()`. The provider watches the Clerk session and fetches the `convex` template token itself; there is no manual login call.
- Sign-in uses Clerk's prebuilt `AuthView` for now. The custom sign-in UI is Phase 1 work; Phase 0 only needs to prove the seam.
- `AuthModel` mirrors the client's `authState`; `ProfileModel` subscribes to the auth-gated query.
- `LaunchLog` marks the handful of real launch milestones (`HavenApp.init`, `LaunchGate`'s first body -- the first frame actually painted -- `Clerk.configure` starting and finishing behind it, `RootView`'s first body, the first Clerk auth-state resolution, the first `profiles:getMyCard` result, and the first appearance of `OnboardingFlow` and of `HavenTabs`) with elapsed time since the first call, once each. To watch it: run from Xcode and filter the console for `launch` (the category), or open Console.app, pick the simulator or device, and filter on subsystem `com.inhavens.haven` -- both read the same `os.Logger` lines, which are marked public specifically so they show up without a special logging profile.
- `Clerk.configure` runs from a `.task` on `LaunchGate`, not from `HavenApp.init`: the SDK's contract is "before `Clerk.shared` is first accessed", not "before anything renders", and `configure` does real synchronous work (a keychain-backed cache load) that used to hold up the very first frame. `RootView` -- the one thing that reads `Clerk.shared` or touches the `convex` global -- is not constructed until `configure` has returned, so the auth gate is unchanged; it now has an extra structural guard in front of it.
