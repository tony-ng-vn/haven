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

## Configure (required before running)

1. Edit `Haven/Config.swift`:
   - `clerkPublishableKey` from the Clerk dashboard (API keys).
   - `convexDeploymentUrl`, e.g. `https://brilliant-puma-925.convex.cloud` (the dev deployment).
   Both values are public and safe to ship in the app binary.
2. In the Clerk dashboard, create a JWT template named `convex` (the Convex integration template).
3. On the Convex deployment, set `CLERK_JWT_ISSUER_DOMAIN` to the Clerk Frontend API URL: `npx convex env set CLERK_JWT_ISSUER_DOMAIN <domain>`.
   This is already read by `convex/auth.config.ts`, which pins `applicationID: "convex"`.

## Run

Build to a simulator or a device.
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
Clerk then fails on `OSStatus -34018: A required entitlement isn't present` inside `Clerk.configure`, which `HavenApp.init` calls before any UI exists.

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
- The contact question's two groups are a fact about the platforms, not a layout choice. X and LinkedIn authorize; Instagram and phone are supplied by hand.
- Whether a username in an authorization payload *is* the handle is a property of the platform, never a guess from whether one happened to arrive. X sends it, so it is stored `verified`. LinkedIn's payload can carry a username that is not the profile address, so it is never taken for one and the confirm panel always opens. Getting that backwards would store an unproven handle as proven.
- Every connectable row has somewhere to land when no trusted handle comes back. A platform that will not tell us who you are there is a reason to ask, never a dead end, so X degrades to a paste exactly as Instagram does.
- `ContactValue` holds the per-platform parsing and is where it is tested; `ContactEntry.parse` is the one place a typed or confirmed value becomes a contact, and it is never `verified`, because a value that had to be typed was by definition not proven by the platform.
- Instagram sits in the typed group because there is nothing to authorize against. Its personal-account API shut down in December 2024 and the replacement covers Creator and Business accounts only, so Clerk offers no Instagram connection at all. `phase1-build-plan.md` has it attempting first and degrading; that was written before the connection turned out not to exist, and attempting would fail for everybody and land in the same paste field one round trip later. The copy still names Instagram's limit rather than implying it is ours.
- `ContactConnector` links an external account with `createExternalAccount` followed by `reauthorize`. That pairing is the SDK's own: the first call makes a pending account carrying the provider's authorization URL, and the second opens it in a browser and waits. This answers the milestone 4 spike in `../phase1-build-plan.md` -- the iOS surface is complete and the hosted-web fallback is not needed.
- Linking is not a fresh act every time it is asked for, so `connect` reloads the user and reuses what Clerk already holds: a verified account short-circuits with no browser trip, a half-linked one gets a fresh authorization rather than a second account, and only a clean slate creates one. In Clerk an external account is also a future sign-in connection, which is why creating duplicates is both wrong and refused. Turning off "Enable for sign-up and sign-in" on the dashboard connection is what keeps a linked handle from quietly becoming a way into the account.
- Nothing on this screen dead-ends. An authorization that fails opens the same panel the no-handle case opens, and Skip is held while a round trip is out, or the answer would land on a screen nobody is looking at.

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

- The profile photo import. Every successful authorization returns an avatar URL, which `ConnectedAccount` carries, but nothing downloads it into Convex storage yet. That needs an upload URL on `profiles` alongside the one `captures` already has.
- Brand glyphs on the contact rows. The rows are text only; the marks are third-party trademarks with their own usage rules, and picking them is its own piece of work.

## Architecture notes

- Dependencies (SPM, pinned in `project.yml`): `ConvexMobile` (convex-swift), `ClerkKit` + `ClerkKitUI` (clerk-ios), `ClerkConvex` (clerk-convex-swift).
- `convex` is a single app-lifetime `ConvexClientWithAuth` using `ClerkConvexAuthProvider()`. The provider watches the Clerk session and fetches the `convex` template token itself; there is no manual login call.
- Sign-in uses Clerk's prebuilt `AuthView` for now. The custom sign-in UI is Phase 1 work; Phase 0 only needs to prove the seam.
- `AuthModel` mirrors the client's `authState`; `ProfileModel` subscribes to the auth-gated query.
