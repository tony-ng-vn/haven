# Phase 1 screens 4-9: parallel execution plan

This plan turns the remaining Phase 1 iOS screens into three waves of work that fresh agent sessions can execute independently.
Wave A builds the shared substrate serially, because everything downstream forks from it.
Wave B fans out into four parallel sessions, one screen each, one PR each.
Wave C holds the work that is either blocked on backend additions or deliberately human-paced.

How to use this file: start a new session, tell it to read this document, and name the wave or unit it owns (for example "execute wave B2 of docs/superpowers/plans/2026-07-27-phase1-parallel-execution.md").
Each wave section is written to be executable without any other conversation context.
The spec authority for everything here is `phase1-build-plan.md` at the repo root; where this plan quotes it, the quote is for convenience and the build plan wins on conflict.

## Standing context for every executor

Read this section first in every session, whatever the wave.

### The development loop

- This repo lives on a Linux server. There is no Xcode here and no way to build or run Swift locally.
- The working tree syncs to the user's Mac via Mutagen in about a second. The user builds, runs the simulator, and screenshots.
- If your session is running on the Mac itself, none of that applies: `xcodegen generate` and `xcodebuild test -project Haven.xcodeproj -scheme Haven -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO` work, and so does looking at the thing. Wave A used a temporary harness for that: swap `RootView`'s body for the view under test and drop `Clerk.configure` from `HavenApp` (it traps in an unsigned build), install to the booted simulator, `./ios/shot.sh <label>`, then restore both files before committing. It found two layout bugs a green build did not.
- Your compile check is CI: the `ios-test` job builds and tests every PR that touches `ios/` on a macOS runner (about 5-7 minutes). Push a PR early and watch `gh pr checks <n>` instead of guessing.
- Your visual check is SwiftUI previews. Every screen ships three: default, `.environment(\.dynamicTypeSize, .accessibility3)`, and `.havenReduceMotion()`. The user judges the real thing on the simulator after merge.
- Adding or removing Swift files requires the user to run `xcodegen generate` on the Mac before building. Note it in the PR body when your change adds files.
- The Convex dev deployment (`brilliant-puma-925`) is shared by every session. `npx convex dev --once` deploys whatever your working tree holds and silently drops functions other branches added. Only deploy from a tree that is current with main, and say so when you do.
- To reset the test profile so onboarding runs again: from the repo root, `: > /tmp/empty.jsonl && npx convex import --replace --table profiles --format jsonLines /tmp/empty.jsonl -y`, and the user runs `xcrun simctl uninstall booted com.inhavens.haven`.

### Repo conventions that apply to all of this work

- Global agent rules in `~/.claude/CLAUDE.md` apply: plain ASCII everywhere, no em dashes, no emoji or decorative symbols, comments explain why, Conventional Commits, incremental self-contained commits, every PR carries a TLDR, never name an agent or tool in commits or PRs.
- Isolate in a worktree: `git worktree add .worktrees/<branch> -b <branch> origin/main`, work there, and remove it after merge. Never work directly on a tree another session may be using.
- The iOS design system rules are documented in `ios/README.md` and are hard requirements: the `HavenColor` palette is closed, serif appears only through `personName(_:)` in `HavenFont.swift`, animation goes through `havenAnimation(_:value:)`, `StarSlot` stays fixed, and content that grows is top-aligned via `HavenScreen`'s `contentAlignment`.
- Tests cover pure logic (parsing, derivation, mapping) in `ios/HavenTests/` using Swift Testing; feel is judged by eye. Convex work is test-first with vitest, runnable on this server: `npx vitest run <file>`, then `npx tsc -p convex/tsconfig.json --noEmit`.
- SF Symbols are fine in UI (`apple.logo` is already used). The no-symbols rule governs prose, commits, and documents, not SwiftUI glyphs.

### State as of 2026-07-27

- Merged on main: onboarding screens 0-3 (welcome, name, location, contact), the design system, `SkyGenerator`/`SkyView`, and the share-capture backend (PR 83).
- Backend already serving and waiting for callers: `profiles:getMyCard`, `updateMyProfile`, `claimHandle`, `getByHandle`; `people:listPeople`, `directoryFacets`, `searchDirectory`, `addPerson`, `editPerson`, `deletePerson`, `saveSharedProfile`.
- Screens 4-9 do not exist. `RootView` currently falls through to the Phase 0 `ProfileProbeView` once onboarding has no unanswered question.
- Known open findings deliberately not yet fixed: onboarding skip state is device-local (needs a server-side progress record), and the OAuth avatar URL is carried but never imported (needs `profiles.generateUploadUrl`). Both are wave C0.

## Wave A: shared substrate (one session, serial, one PR)

Everything in wave B builds against what this wave freezes.
Do the units in order; each is one commit, and the branch is one PR titled `feat(ios): card substrate and app shell`.
Branch: `feat/ios-card-substrate`, from current origin/main.

### A1: move MyCard out of Onboarding

Move `MyCard` (with its nested `City`, `Handle`, `Platform`), `filledSlots`, and nothing else from `ios/Haven/Onboarding/OnboardingModel.swift` into a new file `ios/Haven/Model/MyCard.swift`.
`CityInput`, `ChosenContact`, `OnboardingStep`, `OnboardingSkips`, and the model class stay where they are; they are onboarding's own.
This is a pure move with no behaviour change, in its own commit, per the commit rules.
Why: the card type is about to be shared by the reveal, the edit screen, and the beacon, and a type three surfaces import should not live inside one of them.

Then, in a second commit, add display helpers the card surfaces need, on the moved types:

```swift
extension MyCard.Platform {
    /// "x.com/", "instagram.com/", "linkedin.com/in/", "" for phone.
    var addressPrefix: String
    /// "@handle" for x and instagram, "linkedin.com/in/slug", the number itself for phone.
    func display(_ value: String) -> String
}

extension MyCard.City {
    /// "Austin, TX, United States", dropping the parts that are absent or blank.
    var line: String
}

extension MyCard {
    /// The handle `primaryPlatform` names, or the first one if it names none.
    var primaryHandle: Handle?
}
```

The city line and the primary handle are as-built additions: `HavenCard` needs both, and both are facts about the card rather than about one screen.

`ContactScreen` keeps its private `ContactEntry` prefixes; do not try to unify them in this wave.

### A2: per-star intensity in SkyView

`SkyView` currently takes `litMajors: Set<Int>`: a star is fully lit or a faint dot.
The card reveal is an ignition (stars fading up, staggered, roughly 850ms each per the design tokens), and the edit screen wants the same machinery for its unlit-star nudges, so brightness has to become continuous.

Add to `ios/Haven/Design/SkyView.swift`:

```swift
/// 0 is the unlit faint dot, 1 is fully lit; between is the ignition.
init(sky: Sky, majorIntensities: [Double], figureBand: CGRect? = nil)
```

Rendering contract:
- A major draws its faint dot at `(1 - intensity)` of the current faint opacity, and its lit glow and core at `intensity` times their current alphas. At 0 and 1 the output is pixel-identical to today's two states.
- An edge draws at `min(intensity[a], intensity[b])` times its current 0.24 opacity, so a line never outshines its dimmer star.
- The existing `litMajors` init becomes a convenience that maps to intensities of 0 and 1. Every current caller compiles unchanged.
- Intensities are plain inputs; animating them is the caller's job. Reduce Motion callers pass final values with no animation, as everywhere else.

As built, the mapping lives in `FigureIntensity` in `ios/Haven/Design/SkyMath.swift`, beside the other pure sky maths, and is what the renderer calls:

```swift
enum FigureIntensity {
    static func from(litMajors: Set<Int>, majorCount: Int) -> [Double]
    /// A star the caller said nothing about is unlit, so a short array is safe.
    static func star(_ index: Int, in intensities: [Double]) -> Double
    static func edge(between a: Int, and b: Int, in intensities: [Double]) -> Double
}
```

`SkyLayout.figureExtent` (0.62) is now a named constant rather than a literal inside `init(band:)`, because `CardMetrics` needs the same number.

Cover the mapping (`litMajors` to intensities, edge minimum) in `ios/HavenTests/SkyRenderingTests.swift` alongside whatever it already asserts; rendering itself stays judged by previews.

### A3: HavenCard

New file `ios/Haven/Design/HavenCard.swift`: the person's card as one component, shared by the reveal (4), My Card (7), and the beacon (9).

Layout, per build-plan decision 7 ("The card layout never covers the constellation. Figure owns the top, serif name below it, imported photo small and inline beside the name."):
- The figure on top, held to a band at the top of the card.
- Under it: the name in serif via `personName(_:)`, with an optional small circular photo inline beside it.
- Under that: the city line in muted (name, admin, country joined the way `MyCard.City` has them), then the primary contact as a quiet chip using the A1 display helpers.
- Empty fields simply do not render; the unlit star in the figure is the nudge, per decision 6.

```swift
struct HavenCard: View {
    let card: MyCard
    let sky: Sky
    /// Nil means the complete figure, which is what the reveal and beacon show.
    var majorIntensities: [Double]? = nil
    var photo: Image? = nil
}

/// The card's own metrics, free-standing so the reveal can animate against them.
enum CardMetrics {
    static let figureBandHeight: CGFloat = 340
    static let figureGap: CGFloat = 20
    static let lineGap: CGFloat = 8
    static let photoGap: CGFloat = 10
}
```

As-built correction, and the one thing a caller has to know: the card fills the space it is given rather than sizing a boxed sky inside itself.
The plan said "`SkyView` in a fixed-aspect frame", and that was built first and looked wrong on the simulator: `SkyBackdrop` and `ShimmerField` paint the whole frame they are given, so a bounded sky gives the nebulae and the 128-star minor field a hard rectangular edge, which reads as a rendering mistake rather than as a sky.
The card now lets the sky reach its own edges and passes `figureBand` for the figure alone, which also fixes the figure sitting in the top 62% of its box, since `SkyLayout(band:)` scales by the figure's real extent and `SkyLayout(container:)` does not.
On the reveal and the beacon the card is the screen, so this is what those want.
A caller that is not a whole screen has to hand it a definite height, and an unbounded scroll view is not one; that is C2's to handle.

Previews: complete card, name-only card, accessibility XXXL, Reduce Motion.

### A4: app shell with every wave B route stubbed

New file `ios/Haven/HavenTabs.swift` plus one stub file per screen, so that wave B agents each replace the body of a file they own and never touch shared code.

- `HavenTabs`: a `TabView` with two tabs, People (Directory) and Search, per build-plan open question 3's recommendation.
- Stub files, each compiling as a `HavenScreen` placeholder with the screen's real title and the three standard previews: `ios/Haven/Directory/DirectoryScreen.swift`, `ios/Haven/Search/SearchScreen.swift`, `ios/Haven/Beacon/BeaconScreen.swift`, `ios/Haven/Directory/LockScreenExplainer.swift`, `ios/Haven/Card/MyCardScreen.swift`.
- Navigation already wired in the shell: Directory's toolbar carries a `qrcode` button pushing `BeaconScreen` and a `person.crop.circle` button pushing `MyCardScreen`; the Lock Screen explainer presents as a sheet from Directory.
- `RootView`: when onboarding has no unanswered step, show `HavenTabs` instead of `ProfileProbeView`.
- Delete `ProfileProbe.swift` in the same commit that flips the route; the tabs calling real queries replace the probe's diagnostic job, and dead code does not stay.

As-built corrections to this unit:

- The route flip is in `ios/Haven/Onboarding/OnboardingFlow.swift`, not `RootView.swift`. `RootView` routes on auth state and never mentioned the probe; the fall-through past the last question is `OnboardingFlow`'s, which is also where the card reveal will go. Wave B agents still must not touch `Onboarding/`.
- `ios/Haven/FeatureFlags.swift` is created here rather than in B4, because the shell has to gate the beacon's toolbar entry on `beaconEnabled` and B4 may not edit the shell. B4 still owns the file.
- The explainer sheet's state and presentation live in `DirectoryScreen.swift`, which B1 owns, rather than in the shell. The stub carries a ghost button that opens it, so the route runs today instead of existing unexercised, and B1 replaces that button with the real promo card without touching shared code.
- `project.yml` needs no edit: the target globs `Haven`, so new subdirectories are picked up. The Mac still needs `xcodegen generate` after pulling, because the `.xcodeproj` is git-ignored.
- One repair outside the plan, in its own commit: the two `OnboardingSkips` tests asserted an empty store before writing to it, and `UserDefaults` outlives a test run on the simulator, so they passed once and failed on every run after. They clear the key first now.

Also worth knowing, and deliberately not fixed here: `drawFlares` draws the two diffraction flares at full brightness whatever their star's intensity is, because `SkyFlare` carries coordinates and not a major index.
That is pre-existing and visible in onboarding today, but the card makes it obvious: a spike blazes out of a star that is still an unlit dot.
It matters most to C1, where stars ignite one at a time, so the fix belongs in that session where it can be judged by eye.

### A5: freeze the contract

Finish the wave by editing this plan file: replace the signatures above with the as-built ones if anything moved during implementation, and change the word PLANNED to FROZEN on the line below.
Contract status: FROZEN.
Wave B sessions must refuse to start while this still says PLANNED or the wave A PR is unmerged.

Exit criteria for wave A: `ios-test` green on the PR, previews for HavenCard and the shell exist, the user has merged, and the contract above says FROZEN.

## Wave B: four screens in parallel (four sessions, one PR each)

Rules that bind all four sessions, in addition to the standing context:

- Branch from origin/main only after wave A is merged; verify `ios/Haven/Design/HavenCard.swift` exists on main before writing anything.
- You own exactly the files named in your unit. Do not edit `ios/Haven/Design/`, `HavenTabs.swift`, `RootView.swift`, `project.yml`, another screen, or anything under `Onboarding/`.
- If your screen needs something the design system does not offer, stop and report the need in your PR description instead of adding it. A missing capability is a finding, not an invitation.
- No new package dependencies.
- Copy tone: plain, short, honest; no marketing language, no exclamation marks. Empty states say what is true ("No one saved yet"), never sell.
- PR body: TLDR first, then what the spec asked and where you followed it, then anything you left out and why. Note that no new files were added, or that `xcodegen generate` is needed.
- Watch `gh pr checks` until `ios-test` is green; fix what it finds. Do not report done with red CI.

### B1: Directory screen

Owns `ios/Haven/Directory/DirectoryScreen.swift` and, if promo-card state wants its own file, `ios/Haven/Directory/WidgetPromoCard.swift`.
Branch `feat/ios-directory-shell`.

Spec (build plan screen 5): nav title "People" with a count, a search field that is visual only and switches to the Search tab on focus, an honest empty state ("No one saved yet"), a dismissible Lock Screen widget promo card opening the explainer sheet, and an Add someone button disabled until Phase 2.
Corrections that apply: the empty-state copy must not promise scanning ("Scan someone's code" is Phase 4); the promo pitch covers the beacon and the widget only.

Backend, already deployed:
- `people:listPeople` takes `{ paginationOpts: { numItems, cursor } }` and returns Convex's standard pagination result of person objects. For the shell, load the first page to drive the count and the empty state; full listing UX is Phase 2.
- Subscribe via the shared `convex` client the way `OnboardingModel.loadCard` does, with the same 12-second bounded-wait pattern; an unreachable directory shows a retry state, not a spinner forever.

The explainer sheet is already wired in your file: the stub carries a ghost button that presents it, and the real promo card replaces that button.

Promo-card dismissal persists in `UserDefaults` keyed like `OnboardingSkips` does (see `OnboardingModel.swift`), keyed by user so a second account sees the card fresh.
Note what wave A found the hard way: `UserDefaults` outlives a simulator test run, so a test that asserts an empty store has to clear the key first.
Switching tabs on search-field focus: report in the PR how you did it; if it needs shell support, that is a finding for the PR body, and shipping the field as a non-focusing visual is the acceptable fallback for this wave.

### B2: Search screen

Owns `ios/Haven/Search/SearchScreen.swift`.
Branch `feat/ios-search-shell`.

Spec (build plan screen 6): a search field, a filter chip row, and a results list with serif names and matched-fragment highlighting; Phase 1 ships the layout with the empty state only, wiring arrives in Phase 3.
The chips are company, city, and role, and only those; the prototype's month and context chips are explicitly not to be copied.
Keep the interp-line slot visually reserved per the build plan ("keep the interp line's visual slot reserved but build none of it now").

No backend calls in this wave.
Chips render disabled; the results area shows the empty state.
Serif in the mock results preview goes through `personName(_:)` only, and the preview uses obviously-fake names.

### B3: Lock Screen explainer

Owns `ios/Haven/Directory/LockScreenExplainer.swift`.
Branch `feat/ios-lockscreen-explainer`.

Spec (build plan screen 8): "A picture, not a paragraph": a small Lock Screen mockup with the Haven widget under the clock, one line of copy, "See what it opens" primary, "Not now" ghost, and the three-step how-to one tap deeper.
The mockup is drawn in SwiftUI (rounded rectangle, clock digits, a small widget chip using the design tokens); no image assets, no screenshots of a real lock screen.
`HavenColor.hairlineStrong` exists exactly for a mockup's outer edge (see `HavenColor.swift`).
No backend.
The widget itself is a later milestone; this screen only explains it, and the how-to page states the three steps in plain words.

### B4: Beacon screen

Owns `ios/Haven/Beacon/BeaconScreen.swift` and `ios/Haven/Beacon/QRCode.swift`.
Branch `feat/ios-beacon`.

Spec (build plan screen 9): a real QR encoding `https://inhavens.com/<handle>`, the serif name, the address in mono under it (`havenMono()` exists in `HavenFont.swift`), the line "Show this. They point a camera and land on your card.", and boosted screen brightness while visible.
The handle is `card.username`; it was minted at card creation, so no claim flow is needed here.
QR generation via CoreImage `CIQRCodeGenerator`, error correction level M or better, rendered crisp (nearest-neighbour scale, no interpolation) in ink-on-night colours that still scan; test the generator's output is non-nil and stable for a fixed input in `HavenTests`.
Brightness: raise `UIScreen.main.brightness` on appear, restore the previous value on disappear, and skip the raise entirely when Reduce Motion or Low Power Mode make it hostile (state your choice in the PR).
The whole screen sits behind `FeatureFlags.beaconEnabled` in `ios/Haven/FeatureFlags.swift`, which you own. Wave A created it, false, with the doc comment saying it stays false until the web card page at `inhavens.com/<handle>` exists, per the build plan's new-scope item 3, and the shell already hides the toolbar entry while it is false.

## Wave C: blocked or human-paced

### C0: backend additions (one session, can run in parallel with wave B)

Convex work, test-first, fully verifiable on this server; branch `feat/convex-profile-media-progress`.

1. `profiles.generateUploadUrl`: same shape and rate limiting as `captures.generateUploadUrl`, but its own function; the photo import and My Card photo add call it.
2. `profiles.deleteMyAccount`: deletes the caller's profile row and their owned rows (people, personHandles, captures, sharedNotes participation), returns `null`; App Review 5.1.1 wants the entry point early, and screen 7 carries the row.
3. Onboarding progress record: an `onboarding` optional object on `profiles` (or a sibling table if cleaner) storing per-question `answered | skipped` and a `completedAt`; a mutation `profiles.recordOnboardingStep`; `getMyCard` returns it. This replaces the device-local `OnboardingSkips`, which becomes a cache only. Do not remove the iOS fallback in this branch; the iOS swap is its own later change.
4. Handle normalization convergence, option agreed 2026-07-27: the client keeps its `ContactValue` parsing for live preview, and `updateMyProfile` becomes the authority by folding stored handle values with the same `handleValueKey` rules `people.saveSharedProfile` uses (extract the helpers to `convex/handleKeys.ts` and import from both).

Each item is its own commit with failing test first; `npx vitest run` and the convex typecheck green before the PR.
Do not deploy from the branch; deploy from main after merge.

### C1: the card reveal (screen 4) -- do not hand this to a background agent

Milestone 1 of the build plan: "built first, to the full quality bar, to find the SwiftUI ceiling early", judged on a device, "the best moment in the app".
The acceptance is felt, not assertable, so this is an interactive session with the user running the simulator and screenshotting each iteration, like the welcome screen was built.
Inputs are all ready after wave A: `HavenCard`, `majorIntensities`, `HavenMotion.reveal` timings (settle about 1100ms, scale 1.03 to 1.0, medium haptic, per the design tokens).
Sequence to build: figure ignites star by staggered star, edges follow, the card settles, "This is me" primary advancing into `HavenTabs`, "Add another way to reach me" ghost opening My Card.
Reduce Motion: the card appears complete and still, instantly.
Also in this session: wire onboarding's per-commit star ignition to the new intensities, replacing today's instant flip, since the machinery now exists.

### C2: My Card / edit (screen 7), after C0 merges

Spec (build plan screen 7): the card plus every field, filled or empty; empty fields render as unlit stars with the fixed `StarSlot` mapping; fields are name, photo, city, handles list with primary toggle, company, role; tapping a field edits that field alone, no wizard re-run; the account deletion entry point lives behind a settings row here.
Photo add and the OAuth avatar import both go through `profiles.generateUploadUrl` from C0.
This is agent-executable with the same rules as wave B once C0 is on main; it owns `ios/Haven/Card/MyCardScreen.swift` and whatever field-editor subviews it needs under `ios/Haven/Card/`.

## Independent track, any time

- Privacy policy and terms pages: nothing exists anywhere, App Review 5.1.1 blocks submission without them, and the welcome screen reserves the slot for the links. Web repo work plus two iOS links.
- The public web card page at `inhavens.com/<handle>`: `profiles.getByHandle` already serves it (`{ handle, name, photoUrl, city?, handles, primaryPlatform? }`, phone structurally excluded); `src/` currently has no router, so this is a real web feature. The beacon flag in B4 stays off until this ships.

## Merge and review protocol

- Merge order within a wave does not matter; every branch targets main and none share files.
- After each merge the user runs `xcodegen generate` (every wave B PR adds files it owns) and walks the affected screen on the simulator with `./ios/shot.sh <label>`.
- After all of wave B lands, do one consolidation pass across the four screens together: spacing, copy tone, and empty-state voice drift even under shared components, and that pass is where they converge.

## Model guidance per session

- Wave A: Opus. It is design-system surgery and everything downstream inherits its mistakes.
- Wave B (each of the four): Sonnet is enough; the contract bounds them, and CI catches what it does not.
- Wave C0: Sonnet, test-first.
- Wave C1: Opus, interactive, with the user present.
- Wave C2: Sonnet or Opus depending on how fiddly the field editors get.
