# Backend completion plan: everything convex still owes v1

This is the successor to `2026-07-27-backend-parallel-execution.md`, whose waves A and B all merged (PRs 91, 92, 94, 95).
It covers the distance from main at PR 132 to "the backend is 100% done for the first App Store version".
The shape is the same as before: bounded code units with strict file ownership, decision gates with recommended defaults, and an operations checklist that needs the user and production credentials.

How to use this file: start a session, tell it to read this document, and name the unit it owns.
Each unit is executable without any other conversation context.
Spec authorities on conflict: `mvp-design.md` for the product frame, `phase1-build-plan.md` for the Phase 1 surface, `docs/superpowers/plans/2026-07-26-capture-pipeline-plan.md` for capture.
The PR bodies are the detailed record of every piece of shipped work and its known concerns; when a unit here says "see PR n", read it with `gh pr view <n> --repo tony-ng-vn/haven`.

## Standing context for every executor

- Everything here is fully verifiable on this server: `OPENAI_API_KEY=ci-dummy-key-network-is-mocked npx vitest run <file>` while iterating, then the full suite plus `npx tsc -p convex/tsconfig.json --noEmit` and `npx tsc --noEmit` once at the end.
- Convex work is test-first.
- Read `convex/_generated/ai/guidelines.md` before touching Convex code; its rules override training.
- The Convex dev deployment (`brilliant-puma-925`) is shared by every session. Never deploy from a feature branch; deploy from main after merge, and say so when you do.
- Isolate in a worktree: `git worktree add .worktrees/<branch> -b <branch> origin/main`, run `npm install` there, work there, remove it after merge.
- Repo conventions bind everything: plain ASCII, Conventional Commits, incremental self-contained commits, argument and return validators on every function, no unbounded `.collect()`, every PR carries a TLDR.
- The identity invariant from the previous plan still rules: every write path that touches `contactHandles` maintains `personHandles` in the same transaction.

## A frontend session runs in parallel

A second session is planning and executing the iOS/web side toward the same v1.
The ownership split, binding on both sides:

- This (backend) track owns `convex/`, `scripts/`, `.env.local.example`, and backend plan docs.
- The frontend track owns `ios/` and `src/`.
- Neither edits the other's tree. `todo.md` and `CHANGELOG.md` are shared; keep edits small and merge conflicts honestly.
- A backend contract change that affects a client (validator shape, new function, changed outcome union) must be stated in the PR TLDR and added to the "Contract changes for the frontend" section at the bottom of this file, in the same PR.
- When a frontend plan appears in `docs/superpowers/plans/`, read it before starting your next unit and reconcile: anything it expects of the backend that this plan does not provide is a finding to record here, not silent scope.

## State as of 2026-07-28 (corrects the stale tracker)

Merged on main through PR 132:

- Phases 0-3 backend complete: profile/card (`getMyCard`, `updateMyProfile`, `claimHandle`, `getByHandle`), directory (`listPeople`, `addPerson`, `editPerson`, `deletePerson`, `getPerson`), search (`searchDirectory`, `directoryFacets`), capture (`saveSharedProfile`, screenshot pipeline), network intelligence (`memories`, `semanticSearch`, `people.ask` with eval set).
- Phase 4 connect backend shipped in PR 126: `profiles.connect`, the `connections` edge, both-side directory rows, live-card merge on the detail read, account-deletion collapse to frozen snapshots.
- `people.ask` is wired: iOS calls it from the ask panel (PR 130). The `todo.md` line saying nothing calls it was stale until this plan's tracker sync.
- Stripe subscription mirroring shipped in PR 123: webhook route, `subscriptions` table, `hasProAccess`. No checkout, no StoreKit, no caller of `hasProAccess` anywhere.
- iOS wires 13 backend functions; the web triage/meet surfaces wire most of the rest.
- The full suite is green from a clean checkout: 24 files, 454 tests (run `npm install` first; a stale `node_modules` fails `stripe.test.ts`).

The four verification passes behind this plan (backend inventory, PR-notes concerns, spec-vs-code gaps, iOS expectations) agree on the headline: no phase has an unbuilt backend contract.
What remains is one correctness gap, two bounded hygiene units, five decisions, and an operations checklist that has never touched production.

## Wave A: tracker sync (done in this plan's own PR)

`todo.md` catch-up so parallel sessions stop reading stale state: ask is wired, Phase 4 backend shipped, notes editor and share extension shipped, Stripe exists.
Done as the second commit of the PR that adds this file.

## Wave B: code units (parallel, strict file ownership)

### B1: connect overlay completion (owns convex/profiles.ts, convex/people.ts, their tests; convex/schema.ts only if an index is missing)

Branch `feat/convex-connect-overlay`.
This unit closes the three Phase 4 gaps the spec review found, plus two follow-ups PR 126 itself named.

1. Snapshot fan-out refresh, the one real bug.
   `mvp-design.md` (search contract, overlay model) says search runs over the merged view for connection-backed rows, but `profiles.updateMyProfile` patches only the `profiles` row.
   The `people` rows referencing the user via the `by_havenContactUserId` index keep the connect-time `name`, `normalizedName`, `company/companyKey`, `role/roleKey`, `city/cityKey`, `searchText`, and embedding forever, so a connection who changes jobs is unfindable by their new company.
   Fix: after a profile write, repatch every referencing row's identity and search fields and re-schedule `people.embed` for it.
   Page the fan-out the way `purgeAccountData` pages, so a popular user cannot blow a transaction; test the paging path.
2. Expose connection state on the person payload.
   `personValidator` returns no `havenContactUserId`, so the frontend cannot render connected state, the shared-note affordance, or the frozen-snapshot state after a peer deletes their account.
   Add `havenContactUserId` plus a derived `connection: { peerUsername } | null` (shape at implementer's discretion, recorded below in "Contract changes" once built).
3. Merge the peer's profile handles into the projected connected person (display-side, in `projectConnectedPerson`), so a connection's card shows how to reach them.
   Do not write peer handles into the owner's `contactHandles`; that would churn the identity index with rows the owner never saved.
4. Disconnect (decision gate D5, default: build it).
   Add `profiles.disconnect({ personId })`: drop the edge and the shared note, keep both sides' contact rows as frozen snapshots, return an explicit outcome.
   Today the only way out of a connection is `deletePerson`, which silently destroys the other side's connection and the co-written note; after this unit `deletePerson` on a connected person should delegate to the same teardown and say so in its docstring.
5. Subscriptions on account deletion (decision gate D4b, default: retain).
   `purgeAccountData` deletes everything owned except `subscriptions` rows; make that deliberate with a WHY comment (billing history outlives the account) and a test asserting the retention, or purge them if the user overrides.

### B2: hygiene and hardening (owns convex/crons.ts, convex/loveAlarm.ts, convex/openaiClient.ts, convex/peopleFields.ts, convex/profileFields.ts, .env.local.example, and new tests)

Branch `chore/convex-hygiene`.

1. Cron registration test: `crons.ts` is the only untested module, and a renamed internal function breaks a cron silently.
   Add a test asserting each registered cron resolves to an existing function.
2. loveAlarm presence sweep (decision gate D1, default: keep the table, add the sweep).
   Expired `loveAlarmPresence` rows are filtered on read but never deleted except at account purge; add a bounded internal sweep mutation and a cron for it, in the pattern of `sweepStuckCaptures`.
3. Document every deployment env var in `.env.local.example` with one line each: `STRIPE_WEBHOOK_SECRET`, `STRIPE_SECRET_KEY`, `RESEND_API_KEY`, `WAITLIST_FROM_EMAIL`, and the all-or-nothing `EXTRACTION_*` and `ASK_*` triples.
4. Extraction prompt: define what "headline" means on platforms that do not have one, so an Instagram bio's linked account stops landing there (PR 104's noted concern).
5. Server-side field caps: `updateMyProfile` and `addPerson`/`editPerson` accept unbounded strings where the product caps them (the prototype capped name at 40).
   Cap name and the other free-text card fields server-side to match; pick limits from the iOS field definitions and record them as constants with WHY comments.

### B3: the .unique() flip (gated on wave C step 4; owns one line of convex/people.ts)

Branch `fix/convex-unique-handle-lookup`, its own tiny PR.
Only after production reports zero duplicate handle owners: flip `saveSharedProfile`'s identity lookup from `.first()` to `.unique()`.
Until then `.first()` tolerating duplicates is the documented decision.

## Decision gates

Each has a recommended default so an autonomous run can proceed; every applied default must be flagged in the PR body that applies it, so the user can override at review.

- D1 loveAlarm fate. Default: keep the table and functions, add the expiry sweep (B2.2), decide keep-or-cut with the user before the Phase 6 privacy labels, because presence data must be declared.
- D2 sharedNotes fate. Default: keep. PR 126 made it load-bearing on the `connections` edge and correctly cascaded; cutting it now is work, keeping it is free.
- D3 screenshot triage surface. iOS can create captures (`createCapture`) but has no UI to list, accept, or discard them; only the web triage screen does. The backend is complete either way. This is a frontend/product call: either iOS builds a triage surface, or v1 accepts web-only triage, or shared-to-Haven screenshots are cut from v1. Recorded here so the frontend plan answers it; the backend owes nothing new.
- D4 Stripe scope for v1. Default: park it. It is unspecced in `mvp-design.md`, unreachable from any client, and App Store guideline 3.1.1 means Stripe cannot gate an iOS feature anyway; keep the webhook and mirror as shipped (they are tested and inert), build no checkout and no StoreKit for v1. D4b (subscriptions rows on account deletion) is handled in B1.5.
- D5 disconnect semantics. Default: build `profiles.disconnect` per B1.4.

## Wave C: production operations (with the user; credentials never go to a background agent)

Nothing in this wave is code, and none of it has ever been run against production.
Run in this order from a tree current with main.

1. Unblock prod access: `CONVEX_DEPLOY_KEY` in `.env.local` pins to dev and silently overrides `--prod`.
   Fix by removing the key from `.env.local` and passing keys explicitly per command, or by running prod commands with an explicit `CONVEX_DEPLOY_KEY=<prod key>` prefix.
   Also answer the Vercel question from `todo.md`: whether the Vercel `CONVEX_DEPLOY_KEY` is a production or preview key; a production key means every PR preview deploys the backend to prod.
2. One-off backfills on prod, each to `isDone`: `people:backfillPersonHandles`, `people:backfillSearchText`, `people:backfillNormalizedNames`, `memories:backfillMemories`.
   The embedding backfills are crons and self-heal; do not run them by hand unless a check shows missing vectors.
3. `people:backfillLegacyHandles` to `isDone`, then `people:reportDuplicateHandleOwners`.
   Until this runs, screenshot-accepted and meet-created people twin on their first share.
4. With the duplicate report in hand: reconcile duplicates (merge by hand in the product, or accept them).
   Only at a zero-duplicate report does B3 ship.
5. Stripe prod: create the production webhook endpoint in the Stripe dashboard pointing at `<prod convex site url>/stripe/webhook`, set `STRIPE_WEBHOOK_SECRET` on the prod deployment.
   Skippable only if D4 is overridden to cut Stripe entirely.
6. Waitlist mail on prod: set `RESEND_API_KEY` and `WAITLIST_FROM_EMAIL`.
7. Extraction cutover to Interfaze credit, if still wanted: set the `EXTRACTION_*` triple per `docs/superpowers/specs/2026-07-27-interfaze-cursor-api-research.md`, verify one real screenshot capture end to end, rollback is unsetting the three vars.
8. Clerk production instance, before real users: the four-place swap (`ios/Haven/Config.swift`, Vercel `VITE_CLERK_PUBLISHABLE_KEY`, `CLERK_JWT_ISSUER_DOMAIN` on prod Convex, the CSP entries in `vercel.json`).
   The issuer is half of `tokenIdentifier`, there is no re-keying migration, and none is planned; every existing row orphans at the swap, which is why it happens before real signups or not at all.
   The iOS half of the swap belongs to the frontend track; coordinate the timing.
9. Ask quality, once real notes exist: `OPENAI_API_KEY=sk-... node scripts/eval-ask.ts` for a recall number, one real ask for cost, and recalibrate the 0.3 semantic-search floor against the eval set instead of feel.

## Definition of done for "backend 100% for v1"

- B1 and B2 merged, CI green, tracker current.
- All five decision gates resolved: defaults applied and flagged, or user overrides executed.
- Wave C steps 1-6 executed against production (7-9 are quality/cost work that need real usage or user credit decisions; they may trail TestFlight but must be listed as open in the tracker, not forgotten).
- B3 shipped or explicitly blocked on a nonzero duplicate report with the count recorded in the tracker.
- The "Contract changes for the frontend" section below reflects everything B1 shipped.

## Contract changes for the frontend

Kept current by every backend PR that changes a client-visible shape; the frontend session reads this section, not the diffs.

- PLANNED (B1.2): `personValidator` gains `havenContactUserId` and a `connection` object; shape lands here when built.
- PLANNED (B1.4): new `profiles.disconnect({ personId })` mutation with an explicit outcome union.
- Already true and waiting on frontend wiring, no backend work owed: `people:addPerson` (requires name, handle, and note since PR 86), `profiles:recordOnboardingStep` (device-local skips lose state on reinstall), `profiles:claimHandle` (handle edit UI), `captures:listCaptures`/`acceptCapture`/`acceptManualCapture`/`discardCapture`/`retryExtract` (triage, see D3), `people:getPerson` already returns `photoUrl` and `contactHandles` that iOS drops, `saveSharedProfile.noteTruncated` is computed and discarded client-side, `profiles:connect` has no iOS caller and no scanner or universal-link handler exists.

## Model guidance per unit

- B1: strongest available model; the fan-out touches identity and search invariants where plausible-looking code corrupts data.
- B2: a mid-tier model is fine; every item is bounded and pattern-following.
- B3: trivial, but only after its gate.
- Wave C: interactive with the user present.
