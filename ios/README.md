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

What is worth testing here: pure logic. Sky generation, search filtering, the pending queue, overlay merge.
Springs and haptics are judged by hand on a device, because no assertion captures whether something feels right.

Verified: this scaffold builds green against ConvexMobile 0.8.1, ClerkKit/ClerkKitUI 1.3.2, and ClerkConvex 0.1.0 on the iOS 26.5 simulator.

## Architecture notes

- Dependencies (SPM, pinned in `project.yml`): `ConvexMobile` (convex-swift), `ClerkKit` + `ClerkKitUI` (clerk-ios), `ClerkConvex` (clerk-convex-swift).
- `convex` is a single app-lifetime `ConvexClientWithAuth` using `ClerkConvexAuthProvider()`. The provider watches the Clerk session and fetches the `convex` template token itself; there is no manual login call.
- Sign-in uses Clerk's prebuilt `AuthView` for now. The custom sign-in UI is Phase 1 work; Phase 0 only needs to prove the seam.
- `AuthModel` mirrors the client's `authState`; `ProfileModel` subscribes to the auth-gated query.
