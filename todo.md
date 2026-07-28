# Haven - TODO and backlog

Living work tracker.
The stable design and architecture live in `mvp-design.md`, and Phase 1's implementation detail lives in `phase1-build-plan.md`; this file tracks state: what is done, in progress, and queued.

Checkbox convention: `[ ]` not started, `[~]` in progress, `[x]` done.

## Needs you

Everything here is blocked on a dashboard, a physical device, or a key. No
code is waiting on any of it.

**Dashboards**

- [ ] **Clerk production instance.** Turn off SMS code under Multi-factor first (that is the only thing blocking the free plan). Then create it on `inhavens.com`, set up Apple and LinkedIn OAuth with your own credentials -- production instances do not use Clerk's shared ones -- and recreate the JWT template named exactly `convex`. Then swap the key in four places: `ios/Haven/Config.swift`, `VITE_CLERK_PUBLISHABLE_KEY` on Vercel, `CLERK_JWT_ISSUER_DOMAIN` on the Convex prod deployment, and the three `valued-bonefish-64` entries in `vercel.json`'s CSP. Do it before real users: the issuer is half of `tokenIdentifier`, so every existing row orphans.
- [ ] **Vercel: set `VITE_CONVEX_URL` for the Preview environment.** Settings -> Environment Variables. Preview builds no longer run `npx convex deploy`, so they no longer get that variable handed to them by the deploy step; without it a preview builds but has no database to talk to. Point it at the dev deployment (`https://brilliant-puma-925.convex.cloud`) unless you want previews reading production. The build says exactly this if it is missing rather than shipping a preview that looks fine and does nothing.
- [ ] **Vercel: is `CONVEX_DEPLOY_KEY` a production or a preview key?** Settings -> Environment Variables. Less urgent now that only production deploys Convex, but still worth knowing: if it is a production key it is the key deploying prod on every merge to main, which is what you want; if it is a preview key, production is being deployed by a preview key, which is not.
- [ ] **App Store Connect: reserve the name.** Longest lead time of anything on this list, and "Haven" is crowded.
- [ ] **Apple Developer: enable Sign in with Apple on the App ID.** The entitlement is in the repo; the capability is not something a commit can turn on.
- [ ] **Apple Developer: enable Associated Domains on the App ID, and put the real Team ID in `public/.well-known/apple-app-site-association`.** It ships with `TEAMIDXXXX` because a Team ID is issued to the account that ships the app and cannot live in the repo until somebody puts it there. Until both are done, a scanned Haven code still opens Safari -- which is what it does today, so nothing is worse in the meantime, it is just not yet better.

**Your phone** (an unsigned simulator build cannot configure Clerk, so none of these can be checked without a device)

- [ ] Write a note on someone, then search a word that appears only in that note.
- [ ] Share a profile from Instagram, X and LinkedIn into Haven, and confirm the person lands in the directory.
- [ ] Ask search a question and see whether the answer is any good.
- [ ] **Follow the share-sheet walkthrough's three steps on a real phone and check the wording is what iOS actually shows.** The one device check that can invalidate shipped code rather than merely confirm it: the steps were written against what iOS 26 is believed to show, and nobody has seen that screen.
- [ ] Connect two phones by scanning a card back, and confirm the second scan says you were already connected.
- [ ] Tap each kind of handle on a saved person and confirm where it lands, including a phone number, which the simulator cannot dial at all.
- [ ] Change your Haven address and confirm the code on your card back opens the new page and the old one stops resolving.

The full list, with what each one is for and which change it came from, is the
device ledger in `docs/superpowers/plans/2026-07-28-frontend-completion-plan.md`.
Twenty-three items; these are the ones worth doing first.

**A key**

- [ ] `OPENAI_API_KEY=sk-... node scripts/eval-ask.ts` for a real recall number, and one ask against a real network to measure cost per question. Worth doing only once there are notes to read -- before that it measures nothing.

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
  - [x] 7. Real QR with handle claim, now the back of the card rather than a screen of its own (2026-07-28). The feature flag retired with the screen.
    The QR is dark-on-light rather than inverted: an inverted code reads on an iPhone and not reliably elsewhere, and being scanned by a stranger's phone is its whole job. Still unverified against a non-Apple scanner.
  - [x] 8. Lock Screen widget and deep link. `HavenWidget` target ships with the app.
  - [x] 9. Public web card page at `inhavens.com/<handle>` (`src/CardPage.tsx`), which is what unblocked the beacon flag.
  - [~] Answer the six open questions in the build plan. None block milestone 1. Question 5 is answered and implemented (2026-07-25): reuse `username` as the one handle, with `claimHandle` alongside `setUsername`. The handle UX question is closed (PR 143): the address is a row on My Card, editable, with the server's `taken` outcome and its free suggestions shown as they are. Question 1's silent auto-claim was already built server-side in `updateMyProfile`.
  - [x] Confirmed `ios/` builds green from a clean checkout, and added the `HavenTests` target. Run `xcodegen generate` in `ios/` first: the `.xcodeproj` is git-ignored and generated from `project.yml`, so a stale local copy can look broken when nothing is wrong.
- [x] Backend hygiene and hardening (unit B2, PR 142): a test that catches a cron pointing at a renamed function, an expiry sweep for `loveAlarmPresence`, every deployment env var documented in `.env.local.example`, a definition of "headline" for platforms that have none, and server-side caps on the free-text card fields.
- [~] Decide the fate of the orphaned web product surface.
  Decided 2026-07-25 for `people` and `captures`: promoted, not parked -- `people` is the iOS directory table, extended in place (single-player contacts are standalone owned rows).
  Still open for `loveAlarm` and `sharedNotes`, and for the web UI itself.
  `loveAlarm` keeps its table and gains an expiry sweep (backend gate D1, default applied in PR 142); keep-or-cut is still yours to call, and it is due before the Phase 6 privacy labels because presence data has to be declared either way. `sharedNotes` is decided: keep (gate D2), and PR 139 made it load-bearing on the connections edge.
  `profiles.username` is settled by question 5 (reused as the one handle).
- [x] Housekeeping: pull `main` into the working checkout, then remove the leftover `.worktrees/feat-ios-foundations` worktree and its branch so there is one copy.

## MVP backlog (in order)

- [~] Phase 2: Directory + manual save + contact detail + notes editor. Local pending queue so capture never fails offline.
  This is now the critical path, not just the next item: iOS calls only `listPeople`, `searchDirectory`, and `directoryFacets`, so the app cannot create a person or write a note at all. Until it can, waves A and B have nothing to retrieve.
  - [x] Convex backend: paged directory (`listPeople`), manual save with photo, handles, and structured attributes (`addPerson`), partial edit (`editPerson`), delete with blob cleanup.
  - [x] Convex backend for share capture (capture-pipeline plan milestone 1): `personHandles` identity index, `saveSharedProfile` with created/already/attached outcomes, profile URL parsers with the slug name guess, and the paged `backfillPersonHandles` migration (run after deploy, re-run with the cursor until `isDone`).
  - [x] iOS share extension, App Group queue and mirror, and the main-app drain (capture-pipeline plan milestones 2 and 3). Verified in the simulator; the share sheet's real activation from Instagram, LinkedIn and X still needs a device, and so does the App Group, which the simulator does not enforce.
  - [x] Pin-onboarding walkthrough (capture-pipeline plan milestone 4, PR 148): the More -> Edit -> Favorites path is taught once from the directory's empty state, on a real share sheet, ending in a practice capture. Whether the taught path matches what iOS 26 actually shows is a device check.
  - [ ] Register `group.com.inhavens.haven` in the developer portal and add it to both App IDs (`com.inhavens.haven` and `com.inhavens.haven.share`). The entitlement alone does not provision, and the simulator does not enforce it, so without this every capture is silently dropped on a real device.
  - [x] iOS screens and the local pending queue: person detail with the notes editor (PR 128), completed into the money screen with reach, per-field editing and delete (PR 140), the share extension with its App Group queue and drain (PRs 127, 129), and manual add through the same queue (PR 138).
    Still open on iOS: screenshot captures have no triage surface in the app (web-only; see decision gate D3 in `docs/superpowers/plans/2026-07-28-backend-completion-plan.md`).
    `people:addPerson` stays unused on purpose: a queued write has to be replayable, and `saveSharedProfile` is the mutation that is idempotent on (platform, handle).
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
  - [x] iOS asks: the search screen's ask panel calls `people.ask` and renders matches, bridges, and the quoted evidence line (PR 130). This line previously said nothing called it; that went stale.
  - [ ] Run `scripts/eval-ask.ts` against a live key for a real recall number, and measure cost per ask. Both deliberately outside CI.
- [~] Phase 4: Connect. Mutual auto-connect between two Haven users.
  - [x] Convex backend (PR 126): `profiles.connect`, the `connections` edge, both-side directory rows, live-card merge on the detail read, deletion collapsing to frozen snapshots.
  - [x] Backend follow-ups (unit B1, PR 139): snapshot fan-out so search matches a peer's current card, `connection` state on the person payload, the peer's handles on the merged card, `profiles.disconnect` with `deletePerson` delegating to the same teardown.
    Two known gaps stay open and are written up under "Findings recorded while building B1" in `docs/superpowers/plans/2026-07-28-backend-completion-plan.md`: a peer changing their Haven address leaves the stored handle stale (deferred because refreshing an indexed handle can manufacture the duplicates wave C step 4 must report as zero), and a peer clearing a card field leaves the snapshot holding the old value.
  - [~] iOS: the scanner and `profiles:connect` are wired (PR 146). Still open: no universal-link handler for `inhavens.com/<handle>`, so a Haven QR scanned by the system camera lands in Safari rather than in the app.
- [ ] Stripe subscription mirroring shipped (PR 123: webhook, `subscriptions` table, `hasProAccess`) but nothing reads it, there is no checkout, and App Store guideline 3.1.1 blocks Stripe-gated iOS features. Default decision: parked for v1 (gate D4 in the backend completion plan).
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
