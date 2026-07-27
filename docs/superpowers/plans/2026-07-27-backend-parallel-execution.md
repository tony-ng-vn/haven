# Backend for the MVP: parallel execution plan

This is the backend counterpart to `2026-07-27-phase1-parallel-execution.md`, covering everything the Convex backend still owes the MVP.
The shape is the same: wave A builds one shared seam serially, wave B fans out into parallel sessions with strict file ownership, wave C holds work that is operational, gated on deploys, or a product decision only the user can make.
The good news this plan starts from: the backend is far ahead of the frontend.
Phases 1-3 and capture milestone 1 are served end to end; what remains is one seam, two bounded feature units, one hygiene unit, and an operations checklist.

How to use this file: start a new session, tell it to read this document, and name the wave or unit it owns (for example "execute wave B2 of docs/superpowers/plans/2026-07-27-backend-parallel-execution.md").
Each unit is written to be executable without any other conversation context.
Spec authorities, where quoted: `phase1-build-plan.md` for the Phase 1 surface, `docs/superpowers/plans/2026-07-26-capture-pipeline-plan.md` for capture, `mvp-design.md` for the product frame; those win on conflict.

## Standing context for every executor

Read this section first in every session, whatever the wave.

### The development loop

- Unlike the iOS work, everything here is fully verifiable on this server: `OPENAI_API_KEY=ci-dummy-key-network-is-mocked npx vitest run <file>` while iterating, the full suite plus `npx tsc -p convex/tsconfig.json --noEmit` and `npx tsc --noEmit` once at the end.
- Convex work is test-first: failing test, then the implementation, per the repo rules.
- The Convex dev deployment (`brilliant-puma-925`) is shared by every session. `npx convex dev --once` deploys whatever your working tree holds and silently drops functions other branches added. Never deploy from a feature branch; deploy from main after merge, and say so when you do.
- Read `convex/_generated/ai/guidelines.md` before touching Convex code; its rules override training.
- One known flake, do not weaken the guard: "embed gives up after 3 total attempts" in `convex/people.test.ts` fails only under heavy CPU contention and is green in CI (see todo.md). Unit B3 addresses it properly.

### Repo conventions that apply to all of this work

- Global agent rules in `~/.claude/CLAUDE.md` apply: plain ASCII everywhere, no em dashes, no emoji, comments explain why, Conventional Commits, incremental self-contained commits, every PR carries a TLDR, never name an agent or tool in commits or PRs.
- Isolate in a worktree: `git worktree add .worktrees/<branch> -b <branch> origin/main`, run `npm install` there, work there, remove it after merge. Never work on a tree another session may be using.
- Backend conventions from `CLAUDE.md` at the repo root bind everything: idempotent creation with explicit outcomes, argument and return validators on every function, no unbounded `.collect()`.
- Every write path that touches `contactHandles` maintains `personHandles` in the same transaction. This is the invariant most of this plan exists to finish extending; never ship a write path that breaks it.

### State as of 2026-07-27

- Merged on main: Phase 1 profile backend (`getMyCard`, `updateMyProfile`, `claimHandle`, `getByHandle`, `meetExchange`), Phase 2/3 directory and search backend (`listPeople`, `addPerson`, `editPerson`, `deletePerson`, `searchDirectory`, `directoryFacets`, `semanticSearch`), the screenshot capture pipeline, and capture milestone 1 (`personHandles`, `saveSharedProfile`, URL parsers, `backfillPersonHandles`) via PR 83.
- In flight, and every wave branches only after they merge because they touch wave files: PR 86 (`addPerson` requires name, handle, and note; touches `convex/people.ts` and the web form) and PR 88 (configurable extraction provider; touches `convex/openaiClient.ts`).
- PR 87 is the research doc (`docs/superpowers/specs/2026-07-27-interfaze-cursor-api-research.md`) behind the wave C extraction cutover.
- The known hole this plan closes: three insert paths still write people that are invisible to the identity index - screenshot accepts (`convex/captures.ts`, two inserts) and the meet exchange (`convex/profiles.ts`), all writing legacy `platform`/`handle` scalars and no `personHandles` rows. Re-sharing such a person's profile twins them. Capture-plan open question 4 asked whether to backfill; the blocking half of that question (the fate of `people`/`captures`) was decided 2026-07-25 as promoted, so the backfill is now a yes and only its mechanics need building.
- What is deliberately NOT in this plan because it is not MVP backend: Phase 4 connect flow, capture milestones 5-6 (enrichment, evening follow-up), push notifications, and the web card page (web repo work; `getByHandle` already serves it).

## Wave A: the handle identity seam (one session, serial, one PR)

Branch: `feat/convex-handle-keys`, from origin/main after PRs 86 and 88 merge.
One PR titled `refactor(convex): extract the handle identity seam`.

Everything left in this plan folds handles the same way or it corrupts identity, so the folding rules move to one importable module before anyone else starts.

### A1: extract convex/handleKeys.ts

Move `handleDisplayValue`, `handleValueKey`, and `handleIndexKeys` from `convex/people.ts` into a new `convex/handleKeys.ts`, exported, with their WHY comments intact; `people.ts` imports them.
Pure move, no behaviour change, one commit; the existing people tests are the regression net.

### A2: updateMyProfile folds with the seam

Per the agreement recorded in the phase1 plan (wave C0 item 4): the iOS client keeps its `ContactValue` parsing for live preview, and `profiles.updateMyProfile` becomes the authority by folding stored handle values with `handleValueKey` before writing.
Test first: a profile handle saved as "@Mai.Makes" stores a value whose key equals the key of "mai.makes".
This touches `convex/profiles.ts` once, now, so wave B1 and B2 never both need to.

### A3: freeze the contract

The frozen exports of `convex/handleKeys.ts`:

```ts
export function handleDisplayValue(value: string): string;
export function handleValueKey(value: string): string;
export function handleIndexKeys(handle: { platform: string; value: string }): {
  platform: string;
  valueKey: string;
};
```

Finish the wave by editing this plan file: replace the signatures above with the as-built ones if anything moved, and change the word PLANNED to FROZEN on the line below.
Contract status: PLANNED.
Wave B sessions must refuse to start while this still says PLANNED or the wave A PR is unmerged.

Exit criteria: full suite and both typechecks green, merged, contract says FROZEN.

## Wave B: three parallel units (three sessions, one PR each)

Rules binding all three, in addition to the standing context:

- Branch from origin/main only after wave A is merged; verify `convex/handleKeys.ts` exists on main before writing anything.
- You own exactly the files named in your unit. Do not edit `convex/handleKeys.ts`, `convex/schema.ts` outside the part your unit names, or another unit's files.
- Before starting, run `gh pr list` and check nobody already opened your unit's branch; unit B1 in particular also exists as wave C0 of the phase1 plan, and it must be executed exactly once.
- Test first, every item its own commit, full suite and both typechecks green before the PR, babysit CI until green.

### B1: profiles surface (owns convex/profiles.ts, the profiles table in convex/schema.ts, and their tests)

Branch `feat/convex-profile-media-progress`.
This unit subsumes wave C0 of `2026-07-27-phase1-parallel-execution.md` (items 1-3 there; item 4 landed in wave A here); whichever plan a session was pointed at, the work is this list:

1. `profiles.generateUploadUrl`: same shape and rate limiting as `captures.generateUploadUrl`, but its own function; the OAuth photo import and My Card photo add call it.
2. `profiles.deleteMyAccount`: deletes the caller's profile row and their owned rows (people, personHandles, captures with blobs, sharedNotes participation, rate-limit rows), returns `null`.
   App Review 5.1.1 wants the entry point early, and Phase 1 screen 7 carries the row.
   Deletion is bounded work per table (indexes exist for every owned row); if any table can exceed a transaction's limits, page it the way `backfillPersonHandles` does and say so in the PR.
3. Onboarding progress record: an optional `onboarding` object on `profiles` storing per-question `answered | skipped` and a `completedAt`; a mutation `profiles.recordOnboardingStep`; `getMyCard` returns it.
   The device-local `OnboardingSkips` becomes a cache only; do not touch iOS in this branch.
4. The meet exchange writes the identity index: the person row it creates gains `contactHandles: [{ platform: "haven", value: <username> }]` (folded through `handleIndexKeys`) plus the matching `personHandles` row, in the same transaction, alongside the legacy scalars it writes today.
   A meet-created person must be findable by handle like anyone else, and this closes one of the three index-blind insert paths.

### B2: capture identity unification (owns convex/captures.ts, the maintenance section of convex/people.ts, and their tests)

Branch `feat/convex-legacy-identity`.
This unit executes the now-decided capture-plan open question 4 and the two hard requirements the adversarial review added (see todo.md).

1. Screenshot accepts maintain the index: `acceptCapture` and `acceptManualCapture` write `contactHandles` (from the extracted or typed platform and handle, folded through `handleIndexKeys`) plus `personHandles` rows in the same transaction, alongside the legacy scalars they write today, whenever a handle is present.
   A capture without a visible handle stays name-only; that is honest, not a bug.
2. `people.backfillLegacyHandles` internal mutation, cursor-paged like `backfillPersonHandles` (`{ patched, isDone, cursor }`): for every person whose legacy `platform`/`handle` scalars name an account their `contactHandles` array does not already hold (compare by `handleIndexKeys`), append the entry and insert the index row.
   Idempotent by the same indexKey rule the existing backfill uses; a person whose array already has that platform is skipped and counted separately in the return value, never overwritten.
3. `people.reportDuplicateHandleOwners` internal query: lists `(platform, valueKey)` groups per user owned by more than one person, bounded, so the reconciliation decision in wave C is made on real numbers.
   Report only; merging people is a product decision, not a migration side effect.
4. Do NOT flip the `saveSharedProfile` lookup from `.first()` to `.unique()` in this branch.
   The flip is gated on the wave C reconciliation actually running in production; `.first()` tolerating duplicates is the plan's documented decision until then.

### B3: test-infra hygiene (owns the vitest config only)

Branch `chore/serialize-embed-tests`.
Implement the fix todo.md already names for the known flake: run `convex/people.test.ts` serially (vitest `poolMatchGlobs` or the current equivalent in the repo's vitest version) so the convex-test scheduler race cannot double-start the embed retry job under CPU contention.
Do not weaken the assertion; the app code is correctly bounded and the guard stays.
Delete the todo.md flake entry in the same PR, since the tracker should not outlive the fix.

## Wave C: operations and decisions (human-paced, with the user)

### C0: production operations checklist, in order, after the corresponding merges deploy

Run from a tree that is current with main, with production credentials.

1. After PR 83's deploy (due now): `npx convex run people:backfillPersonHandles '{}'`, re-run with the returned cursor until `isDone`.
   Verify `npx convex run people:backfillSearchText` was run when Phase 3 deployed; run it if not.
2. After PR 88's deploy, the extraction cutover to spend Interfaze credit (full findings and sources in `docs/superpowers/specs/2026-07-27-interfaze-cursor-api-research.md`):
   `npx convex env set EXTRACTION_BASE_URL https://api.interfaze.ai`, `npx convex env set EXTRACTION_API_KEY <interfaze key>`, `npx convex env set EXTRACTION_MODEL interfaze-beta`.
   Then verify one real screenshot capture end to end; the research flagged the image `detail` param and strict `json_schema` with nullable types as the two things to confirm live, and the rollback is unsetting the three vars.
3. After B2's deploy: `npx convex run people:backfillLegacyHandles '{}'` to done, then `npx convex run people:reportDuplicateHandleOwners '{}'`.
4. With that report in hand, decide duplicates: merge the twins by hand in the product, or accept them.
   Only when production reports zero duplicate owners does the `.first()` to `.unique()` flip ship, as its own tiny PR.

### C1: decisions only the user can make

- The fate of `loveAlarm` and `sharedNotes` (the remaining half of the orphaned-web-surface decision, todo.md).
  Nothing in this plan blocks on it, but Phase 6's privacy labels will ask what presence data Haven keeps, so it is due before distribution.
- Clerk dashboard: enable X and LinkedIn sign-in providers (the Phase 1 contact screen already carries the affordances).
- Capture-plan open questions 1-3 (share payload shapes, iOS floor, voice capture placement) are iOS-side and due before capture milestone 2 ships.

## What the backend explicitly does not owe milestones 2-4 of capture

Recorded so nobody builds it: the share extension's queue drain is a client-side loop calling `saveSharedProfile` once per item (plan decision), the extension's mirror is fed by `listPeople`, and screenshot sharing rides the existing captures path.
When milestone 2 starts and something is genuinely missing here, that is a finding for this plan file, not silent scope.

## Merge and review protocol

- Wave A merges alone first. B1, B2, and B3 target main independently and share no files; merge order among them does not matter.
- After every backend merge that the shared dev deployment should reflect, deploy from main (`npx convex dev --once` from an up-to-date main checkout) and say so, per the standing context.
- The wave C checklist runs strictly in its numbered order; each step names the merge it waits for.

## Model guidance per session

- Wave A: Opus. It is a small change, but every downstream unit inherits its mistakes.
- Wave B1: Sonnet; the contract and existing patterns bound it. Account deletion is the one item to slow down on (completeness of owned rows).
- Wave B2: Opus. Migration idempotency and index invariants are exactly where plausible-looking code corrupts identity.
- Wave B3: Sonnet.
- Wave C: interactive with the user present; production credentials never go to a background agent.
