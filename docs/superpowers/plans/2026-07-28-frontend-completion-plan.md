# Frontend completion plan: everything iOS and web still owe v1

This is the frontend counterpart to `2026-07-28-backend-completion-plan.md` (PR 133), covering the distance from main at PR 132 to "the frontend is 100% done for the first App Store version".
The shape follows the repo's execution plans: bounded units with strict file ownership, blocking edges between them, decision gates with recommended defaults, and a ledger of work only the user can do.

How to use this file: start a session, tell it to read this document, and name the unit it owns, or hand the whole file to one orchestrator session and let it drive unit by unit (see "How to run this plan to completion").
Each unit is executable without any other conversation context.
Spec authorities on conflict: `mvp-design.md` for the product frame, `phase1-build-plan.md` for the Phase 1 surface, `docs/superpowers/plans/2026-07-26-capture-pipeline-plan.md` for capture, `docs/superpowers/plans/2026-07-27-network-intelligence-plan.md` for search and ask.
The PR bodies are the detailed record of every shipped piece and its known concerns; when a unit says "see PR n", read it with `gh pr view <n>`.

## Standing context for every executor

- This repo lives on a Linux server with no Xcode; the compile and test check for `ios/` is CI (`ios-test` on a self-hosted mac, minutes per run). Push the PR early and watch `gh pr checks <n>`.
- The working tree syncs to the user's Mac via Mutagen; the user builds, runs the simulator, and judges feel by eye. Simulator claims an agent cannot verify go to the device ledger (below), never into "done".
- Visual verification during a unit is SwiftUI previews: every screen ships three (default, `.environment(\.dynamicTypeSize, .accessibility3)`, `.havenReduceMotion()`).
- The iOS design system rules in `ios/README.md` are hard requirements: the `HavenColor` palette is closed, serif only through `personName(_:)`, animation through `havenAnimation(_:value:)`, `StarSlot` fixed, growing content top-aligned via `HavenScreen`.
- Adding or removing Swift files requires `xcodegen generate` on the Mac before building; say so in the PR body whenever files change.
- Web work (`src/`) is verifiable here: `npx vitest run <file>`, `npx tsc --noEmit`, and the `test` CI job.
- Isolate in a worktree: `git worktree add .worktrees/<branch> -b <branch> origin/main`, work there, remove it after merge. Never work on a tree another session may be using.
- Repo conventions bind everything: plain ASCII, Conventional Commits, incremental self-contained commits, tests first for pure logic (Swift Testing in `ios/HavenTests/`), every PR carries a TLDR and its concerns.
- `CHANGELOG.md` is updated in the same PR for anything a user could notice, per the conventions in `CLAUDE.md`; the version in `package.json` moves with it, and `MARKETING_VERSION` in `ios/project.yml` moves only when an iOS build ships.
- Never deploy Convex from this track. Frontend units never need a deploy; the backend track deploys from main after its merges.

## The backend session runs in parallel

The counterpart session owns `convex/`, `scripts/`, `.env.local.example`, and backend plan docs, per its plan.
This (frontend) track owns `ios/`, `src/`, `public/`, `index.html`, `vercel.json`, `design/`, `brand/`, `.github/workflows/ios.yml`, and frontend plan docs.
`todo.md`, `CHANGELOG.md`, `package.json`, and `.github/workflows/test.yml` are shared; keep edits small and scoped, and resolve merge conflicts by rebasing honestly, never by force.
Neither track edits the other's tree.

Coordination is through the plan docs, per the convention PR 133 set:

- Before starting each unit, fetch main and re-read the "Contract changes for the frontend" section of `2026-07-28-backend-completion-plan.md`; anything PLANNED there that a unit consumes is a blocking edge until it lands.
- Anything this track needs from the backend goes in the "Contract requests for the backend" section at the bottom of this file, in the same PR that discovers the need, and never as a silent edit to `convex/`.
- Backend decision gate D3 (screenshot triage surface) is answered by this plan's gate FD1 below.
- The Clerk production swap (backend plan wave C8) has two frontend-owned halves, `ios/Haven/Config.swift` and the CSP entries in `vercel.json`; unit H1 carries them, and the timing is coordinated with the user because the swap orphans existing rows.
- Version bumps collide by design: both tracks append to `CHANGELOG.md` and bump `package.json`. Whoever merges second rebases and takes the next number; never reuse a version.

## State as of 2026-07-28

Merged on main through PR 134, verified by direct inventory of the code rather than the tracker:

- Phase 1 is fully shipped: onboarding 0-4 with resume and retry, the design system and sky, My Card with field editors and photo upload, the card back QR with flip and drift, the Lock Screen widget and its deep link, the explainer, and the public web card page.
- Capture is shipped end to end: share extension, App Group queue and mirror, main-app drain, screenshot upload path (PRs 127, 129).
- The notes editor is shipped (PR 128); ask is shipped and wired (PR 130); search is wired to `searchDirectory` and `directoryFacets` with working chips (PR 105).
- iOS calls 13 backend functions; CI (`test` and `ios-test`) is green on main.
- PR 134 closed most of the 2026-07-27 card review: row affordances and empty-state legibility, contact-mark sizing and Dynamic Type, the group-label contrast, the title-bar slice, the 340pt card cap (iPad stays supported), the long-name collapse, and the destructive tint on account deletion. Its body names what it left out, and wave G below carries exactly that residue.

What is not built, verified the same way:

- Manual add does not exist: `DirectoryScreen`'s "Add someone" is `.disabled(true)` with an empty action, and nothing on iOS calls `people:addPerson`.
- The person screen is read-only plus the note: `Person` deliberately drops `photoUrl`, `contactHandles`, `preferredPlatform`, and `link` that `getPerson` already returns; there is no reach tap, no field editing, and no delete.
- Search results and ask matches are dead rows: neither `SearchResultRow` nor `AskMatchRow` navigates anywhere, despite carrying the person id.
- Nothing ever claims a Haven handle from iOS: `profiles:claimHandle` has no caller anywhere, so an iOS-only user has no username and the QR on the back of their card encodes an address that resolves to nobody.
- Phase 4 has a backend and no client: no camera or scanner code exists, no universal links (no associated-domains entitlement, no AASA file; a scanned `inhavens.com/<handle>` opens Safari), and nothing on iOS calls `profiles:connect`.
- The pin-onboarding walkthrough (capture milestone 4) does not exist; `ShareSheetModel` sits in `Shared/` waiting for exactly that reuse.
- The welcome screen has no privacy and terms links (App Review 5.1.1(i)); the pages exist and My Card links them.
- `profiles:recordOnboardingStep` is dead on arrival (skips are device-local and lost on reinstall), and the OAuth avatar URL is carried but never imported.
- The directory loads one page of 50 with no paging.
- A release build traps at launch on the placeholder Clerk production key in `Config.swift`, by design, until the user's Clerk production instance exists.

## Blocking graph at a glance

```
frontier now:  nothing; see State
D1 -> D4, E1
D2 -> F3
E2 -> E3, E4, F1
F1 -> F2
backend B1 (PR-133 plan) -> F3
all of D + E1..E3 + F1 -> G1 -> G2 -> G3 -> G4 -> H1 -> H2
```

E4, F2, F3 are not gates for wave G; they join the polish scope if merged by then, and otherwise G3 re-runs its audit on them when they land.

## Wave D: close the single-player core loop

The MVP loop is Capture, Refine, Recall, Reach; today iOS cannot capture by hand, cannot reach, and cannot get from a search result to a person.

### D1: manual add (owns ios/Haven/Directory/DirectoryScreen.swift, new files under ios/Haven/Directory/ or ios/Haven/Capture/, and their tests)

Branch `feat/ios-manual-add`.
Build the "Add someone" flow behind the button `DirectoryScreen` already renders disabled.

- Spec (`mvp-design.md` screens, PR 86 contract): name, one handle on a platform of the user's choice, and a one-line note are all required; the button enables when they are present.
- The offline rule binds: the save writes locally first and never fails at capture time. Reuse the App Group capture queue and main-app drain rather than inventing a second pending path.
- Recommended shape, verify against the validators before committing to it: extend the queue's capture payload with a manual-add case, route it in `ConvexCaptureSink` to `people:addPerson`, and reuse `ShareSheetModel`'s attach-to-existing and dedup behavior where it fits. If the three social platforms cover the input, an alternative is enqueueing the existing `saveSharedProfile` shape; the deciding criteria are offline-first, dedup preserved, free-form platforms supported (WhatsApp and Telegram included, per `mvp-design.md`), and no `convex/` edits.
- The sheet closing is the receipt, per the capture plan; no queue screens, no badges.
- Do not touch the empty-state copy about scanning; that changes in F1.

Done when: a person added in airplane mode appears in the directory after the app next opens online, previews cover the three standard variants, and `ios-test` is green.

### D2: person detail completion (owns ios/Haven/Directory/PersonScreen.swift, PersonModel.swift, new subviews under ios/Haven/Directory/, and their tests)

Branch `feat/ios-person-detail`.
Turn the person screen from "card line plus note" into the money screen `mvp-design.md` describes.

- Render what `getPerson` already returns and iOS drops: photo, contact handles, preferred platform, link.
- Reach: tapping a handle opens the platform (profile URL for socials via the existing `ProfileURL` helpers, `tel:` for phone); the preferred platform leads. This is the fourth stroke of the core loop and it does not exist yet.
- Edit: per-field editors for name, company, role, city, handles, and photo through the `editPerson` partial contract the backend already serves (only `context` is wired today). Follow the My Card field-editor pattern.
- Delete: a confirmed delete via `people:deletePerson`, styled with the restraint the card review asked of destructive rows.
- Keep the notes editor exactly as shipped.
- Explicitly out of this unit: connected-person state (chip, live-card explanation, disconnect); that is F3, gated on backend B1.

Done when: every field the backend serves is visible, editable, and reachable; edits round-trip in tests at the model layer; previews cover the three variants; `ios-test` green.

### D3: search and ask hand back the person (owns ios/Haven/Search/SearchScreen.swift, AskPanel.swift, and their models and tests as needed)

Branch `feat/ios-search-navigation`.
`SearchResultRow` and `AskMatchRow` carry a person id and go nowhere; "hand back the person" is the product's one job.
Make both push the person screen, preserving search state on return.
Done when: a keyword result, a chip-filtered result, and an ask match (direct and bridge) each open the person, and `ios-test` is green.

### D4: directory paging (owns ios/Haven/Directory/DirectoryModel.swift and the list section of DirectoryScreen.swift; blocked by D1)

Branch `feat/ios-directory-paging`.
Page `people:listPeople` with its standard pagination cursor as the list scrolls, keep the count honest (the "N+" form dies once paging exists), and keep the empty and unreachable states as they are.
Blocked by D1 only because both edit `DirectoryScreen`.

### D5: legal links on the welcome screen (owns ios/Haven/Onboarding/WelcomeScreen.swift)

Branch `fix/ios-welcome-legal`.
The phase 1 spec put privacy and terms links small at the bottom of the welcome screen; they were left out when the pages did not exist (PR 74), the pages now exist (PR 119), and `LegalDocument` already carries both URLs.
Two quiet links, VoiceOver labeled, in the muted style My Card uses.
Smallest unit in the plan; a good first PR to validate the loop.

## Wave E: onboarding and capture completion

### E1: the pin walkthrough and practice capture (owns new files under ios/Haven/Capture/, one entry-point edit in DirectoryScreen.swift; blocked by D1)

Branch `feat/ios-pin-walkthrough`.
Capture-plan milestone 4, the only capture milestone left: there is no API to pin a share extension, so teach it once, the way the plan describes.

- A walkthrough opening a real share sheet on a sample profile, steps More -> Edit -> Favorites, mostly pictures per the explainer's precedent.
- Ends with one practice capture that lands a real person in the directory, running the same flow D1 built in-app (this is why `ShareSheetModel` lives in `Shared/`).
- Entry point: the directory empty state alongside the widget promo, dismissible, never a wall.

Blocked by D1 for the in-app sheet reuse and the `DirectoryScreen` file.
Device reality (does Haven appear in Instagram, LinkedIn, X share sheets; does the App Group hold on hardware) goes to the device ledger.

### E2: claim the Haven handle at card creation (owns ios/Haven/Onboarding/OnboardingModel.swift, OnboardingActions.swift, and their tests)

Branch `feat/ios-handle-claim`.
The sharpest gap in the plan: an iOS-only user never gets a username, so their card back encodes a URL that resolves to nobody.
Phase 1 open question 1's recommendation was ratified in spirit and never built: silently auto-claim at card creation.

- On onboarding completion (or first card load with no username), call `profiles:claimHandle` with the suggestion ladder the backend already implements (first name, first-last, numeric suffix), retrying quietly on `taken`.
- No new onboarding screen; the claim is silent, and failure is retried on next launch rather than surfaced mid-reveal.
- Test the ladder and the retry logic at the model layer.

Done when: a fresh signup ends with a username on the card and a QR that resolves; `ios-test` green.

### E3: your address in My Card (owns ios/Haven/Card/MyCardScreen.swift, CardFieldEditors.swift additions, and tests; blocked by E2)

Branch `feat/ios-address-editor`.
The handle-UX half `todo.md` flags as due: show the claimed address as a row in My Card, editable through `claimHandle` with its `taken` outcome and suggestions surfaced honestly.
Changing the address changes the QR and the public page; say so in the editor copy, quietly.

### E4: server-side onboarding progress and the avatar import (owns ios/Haven/Onboarding/OnboardingModel.swift, ContactConnector.swift, related tests; blocked by E2)

Branch `feat/ios-onboarding-server-state`.
Two halves the backend built in PR 92 that iOS never adopted:

1. Call `profiles:recordOnboardingStep` on answer and skip; the device-local `OnboardingSkips` becomes a cache of it, so a reinstall or second phone resumes correctly.
2. Import the OAuth avatar: `ConnectedAccount.imageUrl` is carried for exactly this; download it, upload through `profiles:generateUploadUrl`, patch `photoStorageId`, and light the photo star.
   Never overwrite a photo the user set by hand.

Blocked by E2 for the `OnboardingModel` file.

## Wave F: connect

Phase 4's backend shipped in PR 126; this wave builds its client.
Read PR 126's body before starting any unit here.

### F1: scan and connect (owns new ios/Haven/Connect/ directory, ios/Haven/Info.plist camera usage string, ios/Haven/PrivacyInfo.xcprivacy update, the Directory empty-state copy line, an entry point in DirectoryScreen or HavenTabs; blocked by E2)

Branch `feat/ios-connect-scan`.
The in-person loop: I show you the back of my card, you scan it, we are connected.

- A scanner screen (`DataScannerViewController` is the recommended API at the iOS 17 floor; AVFoundation is the fallback) reading QR payloads and accepting `https://inhavens.com/<handle>` shapes via the existing URL parsing.
- On a recognized handle: fetch the public card via `profiles:getByHandle`, show it as a preview using `HavenCard`, one primary action "Connect".
- Connect calls `profiles:connect` and renders its honest outcomes: `connected` lands the person, `already` says so; the backend creates both directory rows.
- Camera permission is asked at the moment of scanning, never earlier; the usage string is plain about why. `PrivacyInfo.xcprivacy` gains whatever the camera use requires.
- Blocked by E2: `connect` requires the caller to have a username.
- The Directory empty-state copy may now mention scanning; until this merges it must not.

Done when: two simulator accounts can connect via a scanned or pasted handle, each sees the other in their directory, outcome states are tested at the model layer, and the device ledger gains the physical two-phone scan.

### F2: universal links (owns ios/Haven/Haven.entitlements, HavenDeepLink.swift, HavenTabs.swift routing, public/.well-known/apple-app-site-association, vercel.json headers; blocked by F1)

Branch `feat/ios-universal-links`.
A scanned code should open the app when Haven is installed, not Safari.

- `com.apple.developer.associated-domains` with `applinks:inhavens.com`; serve the AASA file from the web app with the right content type, keeping it outside the SPA rewrite (the current rewrite already excludes dotted paths; verify).
- `HavenDeepLink` learns the `https://inhavens.com/<handle>` shape: my own handle opens my card back; another handle opens F1's preview-and-connect screen.
- The AASA needs the Apple Team ID, which is not in the repo: land the file complete with a named placeholder, and put obtaining the ID and provisioning the domain on the user ledger.
- Device verification (universal links do not work in the simulator reliably) goes to the ledger.

### F3: connected-person state (owns ios/Haven/Directory/PersonScreen.swift, PersonModel.swift; blocked by D2 and by backend unit B1 of the 2026-07-28 backend plan)

Branch `feat/ios-connected-state`.
Waits for the backend to expose `havenContactUserId` and the `connection` object on the person payload (PLANNED in its contract section).

- Render connected state: a quiet chip, the peer's live card fields with the merge the backend serves, and the frozen-snapshot state after a peer deletes their account, explained in one line.
- Disconnect, once `profiles.disconnect` lands (backend B1.4), behind the same restraint as delete.
- Editing rules differ on a connected person (their canonical fields are theirs); follow the payload, not assumptions, and record what the backend actually serves in the PR body.
- The shared-note surface is gate FD2, default deferred; do not build it here without an override.

## Wave G: the polish pass (Phase 5)

Runs serially after the feature waves; each unit re-audits before it fixes, because the card and motion system have moved since the last review.
Gate: all of wave D, E1 through E3, and F1 merged.

### G1: card residue (owns ios/Haven/Card/, card-adjacent Design files, the ignition timing in HavenScreen.swift and OnboardingModel.swift, and tests)

Branch `fix/ios-card-residue`.
PR 134 executed the card review's ranked findings and named its leftovers; this unit is those leftovers plus one re-audit.

- The star ignition holds 0.85s while its curve is 96 percent done at 0.40s: about half a second of dead air in the app's signature moment, with two separate timers owning the same beat. PR 134 deferred it as deserving its own pass; this is that pass, judged on device via the ledger.
- The preview-width mismatch from the review (card previews about 19 percent wider than the shipping width): re-verify against current main and align the previews if it stands, so preview judgements are made at the real width.
- FD5, if its default stands: one `ShareLink` on the card back sharing the beacon URL, smallest possible version.
- Re-audit the review doc once against main and record each remaining finding's disposition (fixed, waived, or closed-by 117, 125, 132, or 134) in the PR body; the shadow, spring, and rim findings died with the tilted card per PR 134 and are recorded as such, not reopened.

### G2: motion and haptics (owns ios/Haven/Design/HavenMotion.swift and call sites across screens; blocked by G1)

Branch `feat/ios-motion-pass`.
The review's spring findings were written against the tilted, grabbable card and died with it (PR 134); re-derive the need from the interactions that exist now rather than from the review.

- Audit every interruptible interaction (sheet presentations, tab and navigation transitions, the flip, anything a finger can catch mid-flight); where interruption is real, add spring tokens to `HavenMotion` (the reviewers converged near response 0.4, damping 0.8) and adopt them; keep fixed curves where nothing is interruptible.
- Haptics inventory per the design tokens: light impact on commit, medium on the reveal, nothing elsewhere; verify the new screens (add, connect, walkthrough) obey it.
- Reduce Motion: change arrives instantly everywhere, per the house convention that Reduce Motion removes change, not resting appearance.

### G3: accessibility and type audit (owns fixes across ios/Haven/ screens; blocked by G2)

Branch `fix/ios-a11y-audit`.
Walk every screen including the new D, E, and F surfaces: VoiceOver labels and traits, Dynamic Type through AX sizes, Reduce Motion paths, contrast at the token level.
The six remaining `faint` text call sites PR 134 left across three screens are resolved here, against its `TextContrastTests` standard.
The bar is `PRODUCT.md`: WCAG 2.2 AA equivalents, honest spoken states, no information VoiceOver gets that the eye does not.
Previews are the evidence; findings that need eyes on hardware go to the device ledger.

### G4: copy and convergence (owns copy across ios/Haven/ and src/; blocked by G3)

Branch `fix/ios-copy-pass`.
The consolidation pass wave B got and the new screens have not: empty states, hints, and button copy converge on the house voice (plain, short, honest, no selling).
Also settled here, each recorded in the PR body:

- The explainer's primary copy and destination (PR 97's open call, reshaped by the card back).
- Whether `noteTruncated` from a drained capture surfaces anywhere or stays deliberately silent for v1 (recommend silent; there is no queue surface to carry it, and the person landed).
- The share-sheet name prefill for Instagram and X stays empty by design (PR 129) unless the user overrides.

## Wave H: ship readiness (Phase 6, the code half)

### H1: release readiness (owns ios/project.yml, ios/Haven/Config.swift procedure comments, vercel.json CSP entries, store text drafts under docs/; blocked by G4)

Branch `chore/ios-release-readiness`.

- Verify the release configuration end to end short of signing: the placeholder-key trap is reachable only where intended, export compliance and privacy manifest are current (F1 added camera), and the Release-simulator arm64 note from PR 110 is recorded where CI would trip on it.
- Prepare the Clerk-swap edits as a ready-to-apply change (Config.swift key, vercel.json CSP), coordinated with the backend track's wave C8 timing; the swap itself waits for the user's production instance.
- Draft the store metadata as text under `docs/`: description, subtitle, keywords, category, age rating, support URL, and the screenshot shot list for the user to capture on the Mac.
- Bump `MARKETING_VERSION` per the versioning convention when the submission build is cut, not before.

### H2: the final checklist sweep (owns docs and todo.md edits; blocked by H1)

Branch `chore/ios-submission-checklist`.
Walk the App Store compliance checklist in `mvp-design.md` and the external iOS App Launch Checklist linked in `todo.md`, item by item, against the shipped code.
Produce the final user ledger in `todo.md`: everything left is a dashboard, a key, a device, or App Store Connect, with nothing code-shaped hiding in it.
This unit is the plan's exit audit; its PR body states the exit criteria below with evidence per line.

## Independent units (frontier now, any time)

### I1: retire the unsigned-build flag from CI (owns .github/workflows/ios.yml)

Branch `ci/ios-drop-code-signing-flag`.
PR 116 removed the flag from the docs and left CI carrying `CODE_SIGNING_ALLOWED=NO`, noting its removal "deserves its own PR with a green run".
This is that PR: remove it, watch `ios-test` go green, and note the runtime delta in the PR body.

### I2: web spot-check and small fixes (owns src/, waitlist-design.md notes)

Branch `fix/web-spot-checks`.
Two cheap items PR bodies left open:

- The public card page's unseen states (not-found, a card with handles, a card with a photo): render them locally or against dev data and fix what looks wrong (PR 107).
- The waitlist constellation thinning past roughly 2560 CSS pixels; the fix is already described in `waitlist-design.md` (PR 60).

## Decision gates

Each has a recommended default so an autonomous run can proceed; every applied default is flagged in the PR body that applies it, for the user to override at review.

- FD1, screenshot triage on iOS (answers backend gate D3). Default: v1 keeps screenshot sharing and triage stays web-only; a failed extraction is visible on the web triage screen and invisible on iOS, accepted for the cohort scale. An iOS triage surface is a recorded post-v1 candidate.
- FD2, shared-note surface on iOS. Default: defer past v1. The backend keeps `sharedNotes` (its gate D2); iOS renders nothing for it in v1, and F3 leaves the affordance out.
- FD3, the onboarding sky figure (PRs 73, 90: edges only render between lit stars, so early onboarding reads as scattered dots). Default: leave for v1; it is a taste call the user makes on device, recorded on the ledger.
- FD4, brand glyphs for platforms (PRs 84, 115). Default: text-only stays for v1; real marks are a trademark-usage decision, not a code task.
- FD5, a share action on the card (PR 115 deferred it). Default: build it in G1 as one `ShareLink` on the card back sharing the beacon URL; smallest possible version, cut on any friction.
- FD6, semantic search and evidence in iOS search. Default: not in v1. The MVP search contract is chips plus keyword, ask covers the intelligent path, and `semanticSearch` with evidence stays the recorded first fast-follow per `mvp-design.md` and the network-intelligence plan.

## The device ledger (only the user can run these)

The unsigned simulator cannot configure Clerk, so nothing authenticated has ever run outside a signed build; `todo.md`'s "Needs you" holds the short list, and the full ledger from the PR record is kept here.
Units above append to this list rather than claiming device facts.

1. Note round-trip: write a note, search a word only it contains (PR 128).
2. Share from Instagram, X, and LinkedIn on hardware: does Haven appear in each share sheet, what payload arrives, does the App Group hold outside the simulator (PRs 127, 129; needs the portal App Group registration first).
3. Ask a real question against a real network and judge the answer (PR 130).
4. The card reveal's feel: stagger, settle, haptic (PR 99; the open hero-spike checkbox in todo.md).
5. Scan the card back with another phone, ideally non-Apple, against a production card (PRs 98, 110, 132).
6. The Lock Screen widget on a real Lock Screen, tap landing on the card back (PRs 106, 132).
7. VoiceOver on the card corner marks offering the flip actions (PR 132).
8. Sign in with Apple's success path (needs the portal capability enabled).
9. My Card photo upload and full account deletion end to end (PRs 100, 119; deletion destroys the account it runs on).
10. X and LinkedIn OAuth linking end to end (needs the Clerk connections enabled; also gates E4's avatar import verification).
11. Search against a real signed-in account with real people (PR 105).
12. After F1: the two-phone connect. After F2: a scanned code opening the installed app.
13. Small web check: waitlist constellation touch on a physical iPhone (PRs 63, 65).
14. From PR 134: VoiceOver at accessibility sizes speaking the shed city line with the name, and the 340pt card cap on a real iPad.

New user-side setup this plan adds to the existing "Needs you" list: the Apple Team ID and associated-domains provisioning for F2, and enabling the X connection in Clerk (the existing note names Apple and LinkedIn only).

## Exit criteria: "frontend 100% for v1"

- Every unit in waves D, E, F, G, H, and I merged, or explicitly moved to a decision gate's recorded default or the user ledger.
- All six decision gates resolved: defaults applied and flagged, or user overrides executed.
- The core loop demonstrable on the simulator in one sitting: fresh signup, onboarding to a card with a claimed address, manual add offline, a note, recall by keyword, chip, and ask, opening the person from the result, a reach tap, and a connect between two accounts.
- `test` and `ios-test` green on main; `xcodegen generate` clean; tracker current; the changelog telling the story.
- `todo.md`'s "Needs you" plus the device ledger above are the complete remaining work, and every line in them is a dashboard, key, device, or store task no commit can do.

## How to run this plan to completion (the orchestrator loop)

One session drives; this section is its operating loop, and the goal prompt points here.

1. Sync: `git fetch`; read this plan and the backend plan's contract section at `origin/main`; `gh pr list`; check `gh run list` for main's CI health.
2. Triage: mark units whose PRs merged (flip the checkbox in the state list below via the unit's own PR or a small docs PR); fold any new backend contract changes into the affected units; if a frontend area broke main, fixing it is the frontier.
3. Pick the first open unit whose blockers are all merged, in wave order (D before E before F; G strictly serial; I any time). A unit whose named branch already exists on origin or has an open PR is claimed; skip it.
4. Execute it exactly as specified: worktree, test-first for logic, previews for screens, incremental commits, PR with TLDR and concerns, `gh pr checks` babysat to green.
5. While a PR waits for merge, start the next unblocked unit; never branch a unit off an unmerged PR.
6. A needed backend change goes to "Contract requests for the backend" below, in a docs commit, and the unit blocks; never edit `convex/`.
7. Anything only the user can do goes to the device ledger or "Needs you", named precisely, and work continues elsewhere.
8. After a merge: remove the worktree, delete the branch, update the state list.
9. Stop and report only when the exit criteria hold, or when every remaining unit is blocked on the user; in that second case, list exactly what is waited on.

## State

- [x] D1 manual add (PR 138)
- [x] D2 person detail completion (PR 140)
- [x] D3 search and ask navigation (PR 141)
- [x] D4 directory paging (PR 147)
- [x] D5 welcome legal links (PR 137)
- [x] E1 pin walkthrough and practice capture (PR 148)
- [x] E2 handle claim at card creation -- void on inspection (PR 143)
- [x] E3 address editor in My Card (PR 143)
- [x] E4 server onboarding state and avatar import (PR 144)
- [x] F1 scan and connect (PR 146)
- [ ] F2 universal links
- [ ] F3 connected-person state (needs backend B1)
- [ ] G1 card review fixes
- [ ] G2 motion and haptics
- [ ] G3 accessibility audit
- [ ] G4 copy convergence
- [ ] H1 release readiness
- [ ] H2 final checklist sweep
- [x] I1 CI signing-flag removal (PR 136)
- [x] I2 web spot-checks (PR 145)

## Contract requests for the backend

Kept current by every frontend PR that discovers a need; the backend session reads this section, not our diffs.

- None blocking today: every unit above builds against functions already on main, plus the two PLANNED items the backend plan already carries for F3 (`havenContactUserId` and `connection` on the person payload; `profiles.disconnect`).
- Non-blocking, recorded for backend hygiene: the `verified` flag on handles is client-asserted through `updateMyProfile` and published on the public card (PR 69 said it should become server-derived once OAuth landed); at cohort scale this is accepted for v1.

## Model guidance per unit

- Strongest available model: D1, D2, E1, F1, F2, G1, G2 (queue semantics, money screens, entitlement correctness, and design-system surgery).
- Mid-tier is fine: D3, D4, E2, E3, E4, F3, G3, G4, H1, H2, I1, I2 (bounded, pattern-following, or docs-shaped).
- The reveal-adjacent taste calls (FD3, the G-wave feel checks) are judged by the user on device, never asserted by an agent.
