# Haven - TODO and backlog

Living work tracker.
The stable design and architecture live in `mvp-design.md`, and Phase 1's implementation detail lives in `phase1-build-plan.md`; this file tracks state: what is done, in progress, and queued.

Checkbox convention: `[ ]` not started, `[~]` in progress, `[x]` done.

## Now / next

- [~] Phase 1: Onboarding, card, and the two home screens. Full spec and milestone definitions of done in `phase1-build-plan.md`.
  - [x] Design settled: interactive prototype at `design/onboarding-prototype.html`, decisions ratified in the build plan.
  - [ ] 1. Hero spike: card reveal against hardcoded data, full quality bar. Done when it feels right on a physical device.
  - [~] 2. Design system: color and type tokens, shared controls, screen skeleton, dust layer, sky renderer ported from `src/sky.ts` with fixed star slots.
    - [x] Sky generator ported to Swift, asserted against vectors dumped from the TypeScript so the app and the future web card page cannot drift apart.
    - [ ] SwiftUI renderer for it, plus the fixed star-slot mapping (name 0, city 1, contact 2, photo 3, company 4, role 5).
    - [ ] Colour and type tokens, Field, PrimaryButton, GhostButton, Row, screen skeleton, dust layer.
  - [x] 3. Convex schema and functions, test-first, including `claimHandle`.
    Already on main (`updateMyProfile`, `claimHandle` with the suggestion ladder, public `getByHandle`); this checkbox had gone stale.
  - [ ] 4. Onboarding wired end to end, all four contact paths, with resume and retry.
  - [ ] 5. My Card / edit with unlit-star states, handle management, photo add.
  - [ ] 6. Directory and Search shells, widget promo card, Lock Screen explainer.
  - [ ] 7. Beacon screen with real QR and handle claim (flagged off until the web card page exists).
  - [ ] 8. Lock Screen widget and deep link.
  - [ ] 9. Public web card page at `inhavens.com/<handle>` (web repo, parallel track after milestone 3).
  - [~] Answer the six open questions in the build plan. None block milestone 1. Question 5 is answered and implemented (2026-07-25): reuse `username` as the one handle, with `claimHandle` alongside `setUsername`. The handle UX question is due before milestone 4.
  - [x] Confirmed `ios/` builds green from a clean checkout, and added the `HavenTests` target. Run `xcodegen generate` in `ios/` first: the `.xcodeproj` is git-ignored and generated from `project.yml`, so a stale local copy can look broken when nothing is wrong.
- [~] Decide the fate of the orphaned web product surface.
  Decided 2026-07-25 for `people` and `captures`: promoted, not parked -- `people` is the iOS directory table, extended in place (single-player contacts are standalone owned rows).
  Still open for `loveAlarm` and `sharedNotes`, and for the web UI itself.
  `profiles.username` is settled by question 5 (reused as the one handle).
- [ ] Housekeeping: pull `main` into the working checkout, then remove the leftover `.worktrees/feat-ios-foundations` worktree and its branch so there is one copy.
- [ ] Known flake, do not weaken the guard: "embed gives up after 3 total attempts" in `convex/people.test.ts` fails intermittently only under heavy CPU contention (a convex-test scheduler race can start the same scheduled job twice; the app code is correctly bounded). Green in CI. Fix belongs upstream in convex-test or by serializing that file, not by loosening the assertion.

## MVP backlog (in order)

- [~] Phase 2: Directory + manual save + contact detail + notes editor. Local pending queue so capture never fails offline.
  - [x] Convex backend: paged directory (`listPeople`), manual save with photo, handles, and structured attributes (`addPerson`), partial edit (`editPerson`), delete with blob cleanup.
  - [x] Convex backend for share capture (capture-pipeline plan milestone 1): `personHandles` identity index, `saveSharedProfile` with created/already/attached outcomes, profile URL parsers with the slug name guess, and the paged `backfillPersonHandles` migration (run after deploy, re-run with the cursor until `isDone`).
  - [ ] iOS share extension, App Group queue and mirror, pin-onboarding walkthrough (capture-pipeline plan milestones 2-4).
  - [ ] iOS screens and the local pending queue.
  - [ ] Settle capture-plan open question 4 soon - it is load-bearing now: people from screenshot captures and meet exchanges carry only the legacy `platform`/`handle` scalars and get no `personHandles` rows, so sharing the same profile later twins them. Decide the legacy-to-`contactHandles` backfill before the iOS share extension ships.
- [~] Phase 3: Search. Filter chips (company / city / role) plus keyword over notes. See the search contract in `mvp-design.md`.
  - [x] Convex backend: `searchDirectory` (keyword + chips, accent-folded) and `directoryFacets` (chip values). Run `npx convex run people:backfillSearchText` once after deploy so pre-existing people join the keyword index.
  - [ ] iOS search screen wiring.
- [ ] Phase 4: Connect. Mutual auto-connect between two Haven users.
- [ ] Phase 5: Polish pass. Haptics, transitions, gesture physics across the app.
- [ ] Phase 6: Distribution. TestFlight to the waitlist cohort, then App Store.
  - [ ] Go through the full iOS App Launch Checklist before submitting (Cole Caccamise): https://colecaccamise.notion.site/The-iOS-App-Launch-Checklist-3786e16e7a578019a96ac84819de934a
  - [ ] App Store compliance basics are already listed in `mvp-design.md` (in-app account deletion, Sign in with Apple, privacy labels, permission strings).

## Prototype checkpoints

These are LOGIC prototypes (a tiny hand-driven terminal app over the pure logic), done at the phase noted, not before.
Rule: prototype when guessing wrong is costly and hard to undo; skip when the answer is clear or cheap to reverse.
UI and feel questions go through SwiftUI previews in Xcode, not the web-oriented prototype skill.

- [x] Before Phase 2 - contacts data model. HIGH value.
  Resolved by the single-player-first decision (2026-07-25): a contact is a standalone owned row on the existing `people` table, extended in place; no separate contacts table and no overlay yet.
  The overlay questions (connect populating both sides, deletion collapsing to a frozen snapshot) move to a prototype before Phase 4 Connect; the reference seam (`havenContactUserId`) already exists on `people`.
- [ ] Roadmap - calendar smart-matching heuristic (when we build it).
  Q: does "connection time + your calendar event at that time -> pre-filled met at X" behave across back-to-back, all-day, no-event, and overlapping cases?
- [ ] Roadmap - swipe review queue state model (when we build it).
  Q: how does a contact move pending -> kept or skipped, and how does dwell-time grouping decide who you actually talked to? (The swipe feel itself is an Xcode question.)

## Roadmap (post-MVP, parked)

- [ ] App Clip connect-back: a non-user joins the connection in the moment with one Sign-in-with-Apple tap, no install wall.
- [ ] Semantic / natural-language search over memories (Convex vector search).
- [ ] Swipe review queue + voice capture (the upgrade of Refine).
- [ ] LinkedIn enrichment: paste a profile link, scrape it into searchable data.
- [ ] Calendar smart-matching: pre-fill "met at X" from connection time + calendar.
- [ ] Selective card sharing: per-person control over which fields a connection reveals.
- [ ] Rotating connect tokens: close the screenshot-replay hole.
- [ ] Bluetooth radar: foreground event mode first; wearable beacon only if demand proves out.
- [ ] Social / matching layer: opt-in, machine-only, abstract matches without exposing the underlying data.
- [ ] v4 idea: the system reads your messages to suggest people (noted only so we do not lose it).

## Done

- [x] MVP design doc - `mvp-design.md` (PR #49).
- [x] Phase 0: iOS foundations. Native SwiftUI app; the Clerk -> Convex auth seam is verified working on a signed simulator build. Two fixes were needed: the convex-templated Clerk token and the keychain-access-groups entitlement (PR #52). Scaffold in PR #50, config keys in PR #51.
