# Haven - TODO and backlog

Living work tracker.
The stable design and architecture live in `mvp-design.md`, and Phase 1's implementation detail lives in `phase1-build-plan.md`; this file tracks state: what is done, in progress, and queued.

Checkbox convention: `[ ]` not started, `[~]` in progress, `[x]` done.

## Now / next

- [~] Phase 1: Onboarding, card, and the two home screens. Full spec and milestone definitions of done in `phase1-build-plan.md`.
  - [x] Design settled: interactive prototype at `design/onboarding-prototype.html`, decisions ratified in the build plan.
  - [ ] 1. Hero spike: card reveal against hardcoded data, full quality bar. Done when it feels right on a physical device.
  - [x] 2. Design system: color and type tokens, shared controls, screen skeleton, dust layer, sky renderer ported from `src/sky.ts` with fixed star slots.
    - [x] Sky generator ported to Swift, asserted against vectors dumped from the TypeScript so the app and the future web card page cannot drift apart.
    - [x] SwiftUI renderer for it, plus the fixed star-slot mapping (name 0, city 1, contact 2, photo 3, company 4, role 5).
    - [x] Colour and type tokens, Field, PrimaryButton, GhostButton, Row, screen skeleton, dust layer.
  - [x] 3. Convex schema and functions, test-first, including `claimHandle`.
    Already on main (`updateMyProfile`, `claimHandle` with the suggestion ladder, public `getByHandle`); this checkbox had gone stale.
  - [x] 4. Onboarding wired end to end, all four contact paths, with resume and retry.
  - [x] 5. My Card / edit with unlit-star states, handle management, photo add.
    Photo upload and account deletion still need a signed-in session to exercise; the unsigned simulator cannot.
  - [x] 6. Directory and Search shells, widget promo card, Lock Screen explainer.
  - [x] 7. Beacon screen with real QR and handle claim (flagged off until the web card page exists).
    The QR is dark-on-light rather than inverted: an inverted code reads on an iPhone and not reliably elsewhere, and being scanned by a stranger's phone is the screen's whole job. Still unverified against a non-Apple scanner.
  - [x] 8. Lock Screen widget and deep link. `HavenWidget` target ships with the app.
  - [x] 9. Public web card page at `inhavens.com/<handle>` (`src/CardPage.tsx`), which is what unblocked the beacon flag.
  - [~] Answer the six open questions in the build plan. None block milestone 1. Question 5 is answered and implemented (2026-07-25): reuse `username` as the one handle, with `claimHandle` alongside `setUsername`. The handle UX question is due before milestone 4.
  - [x] Confirmed `ios/` builds green from a clean checkout, and added the `HavenTests` target. Run `xcodegen generate` in `ios/` first: the `.xcodeproj` is git-ignored and generated from `project.yml`, so a stale local copy can look broken when nothing is wrong.
- [~] Decide the fate of the orphaned web product surface.
  Decided 2026-07-25 for `people` and `captures`: promoted, not parked -- `people` is the iOS directory table, extended in place (single-player contacts are standalone owned rows).
  Still open for `loveAlarm` and `sharedNotes`, and for the web UI itself.
  `profiles.username` is settled by question 5 (reused as the one handle).
- [x] Housekeeping: pull `main` into the working checkout, then remove the leftover `.worktrees/feat-ios-foundations` worktree and its branch so there is one copy.

## MVP backlog (in order)

- [~] Phase 2: Directory + manual save + contact detail + notes editor. Local pending queue so capture never fails offline.
  This is now the critical path, not just the next item: iOS calls only `listPeople`, `searchDirectory`, and `directoryFacets`, so the app cannot create a person or write a note at all. Until it can, waves A and B have nothing to retrieve.
  - [x] Convex backend: paged directory (`listPeople`), manual save with photo, handles, and structured attributes (`addPerson`), partial edit (`editPerson`), delete with blob cleanup.
  - [x] Convex backend for share capture (capture-pipeline plan milestone 1): `personHandles` identity index, `saveSharedProfile` with created/already/attached outcomes, profile URL parsers with the slug name guess, and the paged `backfillPersonHandles` migration (run after deploy, re-run with the cursor until `isDone`).
  - [x] iOS share extension, App Group queue and mirror, and the main-app drain (capture-pipeline plan milestones 2 and 3). Verified in the simulator; the share sheet's real activation from Instagram, LinkedIn and X still needs a device, and so does the App Group, which the simulator does not enforce.
  - [ ] Pin-onboarding walkthrough (capture-pipeline plan milestone 4): there is no API to pin or reorder a share extension, so the More -> Edit -> Favorites path has to be taught once, ending in a practice capture.
  - [ ] Register `group.com.inhavens.haven` in the developer portal and add it to both App IDs (`com.inhavens.haven` and `com.inhavens.haven.share`). The entitlement alone does not provision, and the simulator does not enforce it, so without this every capture is silently dropped on a real device.
  - [ ] iOS screens and the local pending queue.
  - [ ] Run `people:backfillLegacyHandles` to `isDone` on prod. This is capture-plan open question 4, and the code half is settled - the migration exists and is tested - but it has not been run: `people:reportDuplicateHandleOwners` returns `scanned: 0` against dev, and prod is unchecked because `CONVEX_DEPLOY_KEY` in `.env.local` pins to dev and overrides `--prod`.
    Until it runs, people saved from screenshot captures and meet exchanges carry only the legacy `platform`/`handle` scalars with no `personHandles` rows, so the first share of the same profile twins them.
    Adversarial review adds two requirements for that work: every direct `people` insert path (screenshot acceptance included) must maintain `personHandles` in the same transaction, and existing duplicate `(userId, platform, valueKey)` owners must be reconciled before the capture lookup can move from `.first()` to `.unique()`.
- [~] Phase 3: Search. Filter chips (company / city / role) plus keyword over notes. See the search contract in `mvp-design.md`.
  - [x] Convex backend: `searchDirectory` (keyword + chips, accent-folded) and `directoryFacets` (chip values). Run `npx convex run people:backfillSearchText` once after deploy so pre-existing people join the keyword index.
  - [x] iOS search screen wiring.
    Keyword covers name, company, role, city, handles, and the "where we met" context. It will reach further once Phase 2's notes editor gives it more to index.
  - [x] Network intelligence wave A: `memories` table, one vector per note line, per-memory embeddings, and `semanticSearch` returning the line that matched as `evidence`. Plan: `docs/superpowers/plans/2026-07-27-network-intelligence-plan.md`.
    Migration run against `brilliant-puma-925` on 2026-07-27: 0 patched, 0 skipped. Correct and empty -- no person has a note yet, because the only note field in the product is the web triage screen and it is skippable.
  - [x] Network intelligence wave B: `people.ask` over the whole network in one call, direct matches plus bridges with their reasoning, one clarifying question instead of a guess, and a checked-in eval set (`src/askFixtures.ts`, `scripts/eval-ask.ts`).
  - [ ] Nothing calls `people.ask` yet, and nothing renders `evidence`. iOS search reads `searchDirectory`, which returns neither. Blocked behind Phase 2's notes editor by choice: a question box over a network with no notes has nothing to answer from.
  - [ ] Run `scripts/eval-ask.ts` against a live key for a real recall number, and measure cost per ask. Both deliberately outside CI.
- [ ] Phase 4: Connect. Mutual auto-connect between two Haven users.
- [ ] Phase 5: Polish pass. Haptics, transitions, gesture physics across the app.
- [ ] Phase 6: Distribution. TestFlight to the waitlist cohort, then App Store.
  - [ ] Go through the full iOS App Launch Checklist before submitting (Cole Caccamise): https://colecaccamise.notion.site/The-iOS-App-Launch-Checklist-3786e16e7a578019a96ac84819de934a
  - [~] App Store compliance, tracked in `mvp-design.md` under "App Store compliance checklist".
    The code half is done ahead of this phase on purpose: those items hold still while the product changes, unlike store metadata, which the Phase 5 polish pass invalidates.
    What is left there is dashboard and portal work, and three items are worth starting now rather than at submission.
  - [ ] Reserve the app name in App Store Connect. Longest lead time of anything on the list, and "Haven" is crowded.
  - [ ] Create the Clerk production instance. Web and iOS both run on a development instance today, which caps its user count and cannot be migrated off, so every day of signups makes it worse.
  - [ ] Enable Sign In with Apple on the App ID and verify sign-in on a physical device. The entitlement is in the repo; the capability is not something a commit can turn on.

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
