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
Signed out, you get Clerk's prebuilt `AuthView`.
Signed in, the app calls `profiles:getMyProfile` (auth-gated by `requireUser`) and shows one of three outcomes:

- `Profile: @username` -- unambiguous proof the authenticated Convex call succeeded end to end.
- "Signed in, query ran, no profile row yet" -- the call also succeeded; you just have no profile row.
- A red "Convex call failed" with an error -- Clerk minted a token but Convex rejected it. Check the `convex` JWT template and `CLERK_JWT_ISSUER_DOMAIN`.

To exercise the live-update half of the Phase 0 DoD: sign in on the phone, then change your username on the web app (or in the Convex dashboard) and watch the phone update on its own, with no refresh.

### Signing for a physical device

`xcodegen generate` rewrites the project, so a signing team set by hand in Xcode is wiped on each regenerate.
Either set your team once in Signing & Capabilities after generating, or add `DEVELOPMENT_TEAM` to `project.yml`.

## Compile-check from the command line

Always run `xcodegen generate` first.
The `.xcodeproj` is git-ignored, so a copy left over from an earlier checkout can be missing files that exist on disk, and the build then fails for a reason that is not real.

```sh
xcodegen generate
# Use any installed simulator (xcrun simctl list devices); iPhone 17 ships with the iOS 26.5 runtime.
xcodebuild build -project Haven.xcodeproj -scheme Haven \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

## Tests

```sh
xcodegen generate
xcodebuild test -project Haven.xcodeproj -scheme Haven \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

Swift Testing, in the `HavenTests` target.
The unit tests are hosted in the app, so launching them starts Clerk, which logs `OSStatus -34018` keychain failures when code signing is off.
That noise is expected in a test run and does not affect the results; on a signed build the entitlement is present.

CI runs these tests in `.github/workflows/ios.yml`, on any pull request that touches `ios/`.
A pull request that touches no Swift skips the job, because macOS runners are billed at several times the Linux rate.

What is worth testing here: pure logic. Sky generation, search filtering, the pending queue, overlay merge.
Springs and haptics are judged by hand on a device, because no assertion captures whether something feels right.

Verified: this scaffold builds green against ConvexMobile 0.8.1, ClerkKit/ClerkKitUI 1.3.2, and ClerkConvex 0.1.0 on the iOS 26.5 simulator.

## Design system

Everything in `Haven/Design` is milestone 2 of `../phase1-build-plan.md`, and everything downstream imports its vocabulary rather than inventing its own.

- `HavenColor` is the committed dusk palette. The list is closed: a surface that seems to need a new hue almost always needs an existing one at a different opacity.
- `HavenFont` holds the type rules as view modifiers, not raw fonts, for one reason: it keeps `.serif` inside that one file. Serif (New York) is reserved for people's names via `personName(_:)`, and everything else is SF Pro. A grep for "serif" anywhere else in `Haven/` should return nothing. Every style is built from a relative text style, so Dynamic Type scales all of it.
- `HavenMotion` holds the four durations and the strong ease-out. Use `havenAnimation(_:value:)` instead of `.animation(_:value:)` and Reduce Motion is handled for you: the state change still happens, it just arrives instantly.
- `NightBackground` and `DustLayer` are the atmosphere. Neither ever responds to progress.
- `SkyView` renders a `Sky` from `SkyGenerator`. It draws the sky at rest and deliberately knows nothing about ignition order or the card reveal.
- `StarSlot` fixes which figure star each profile field owns. Do not make it dynamic; the edit screen's unlit stars are only legible because a field's star never moves.
- `HavenScreen`, `HavenField`, `PrimaryButton`, `GhostButton` and `HavenRow` are the shared controls.

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

Built so far: screen 0 (welcome), screen 1 (name), screen 2 (location). Contact and the card reveal are next; until they exist, a person through the first two falls through to the Phase 0 probe.

## Architecture notes

- Dependencies (SPM, pinned in `project.yml`): `ConvexMobile` (convex-swift), `ClerkKit` + `ClerkKitUI` (clerk-ios), `ClerkConvex` (clerk-convex-swift).
- `convex` is a single app-lifetime `ConvexClientWithAuth` using `ClerkConvexAuthProvider()`. The provider watches the Clerk session and fetches the `convex` template token itself; there is no manual login call.
- Sign-in uses Clerk's prebuilt `AuthView` for now. The custom sign-in UI is Phase 1 work; Phase 0 only needs to prove the seam.
- `AuthModel` mirrors the client's `authState`; `ProfileModel` subscribes to the auth-gated query.
