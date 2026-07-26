# Capture Pipeline Build Plan

Date: 2026-07-26
Status: Plan, ready to build
Scope: the first Phase 2 slice - getting people into Haven from the platforms the user already uses
Research behind it: `docs/superpowers/specs/2026-07-26-capture-input-research.md`

## The goal in one line

The user connects with people wherever they already do (Instagram, LinkedIn, X, in person), and Haven becomes the one place all of them live, searchable by anything remembered about them.

## The person model

**One person is one row. Platforms are attributes on that row, never separate records.**

A person in Haven is not "an Instagram contact" or "a LinkedIn contact"; they are a person the user met, who happens to be reachable on some set of platforms.
So sharing a second platform for someone already saved is not a merge or a dedup problem - it is adding a handle to an existing person.
This is what centralizing means: the value of Haven is that the platform stops mattering once the person is inside.

Consequences that follow from this and settle several smaller questions:

- `contactHandles` on the existing `people` row is the right home for platform identities, and it already enforces one handle per platform.
- The card shows the person, with their platforms as ways to reach them; `preferredPlatform` decides which one the Reach tap opens.
- Search is over the person, never per-platform.
- The legacy single `platform` / `handle` fields on `people` (from the web-era capture pipeline) are the odd ones out; new writes use `contactHandles`, and the legacy pair stays untouched for existing rows.

## Decisions

### 1. A shared profile writes straight to `people`, with no staging table

The `captures` table exists because screenshot extraction is asynchronous and can fail, so a screenshot needs a pending state with a retry path.
A shared URL has nothing asynchronous about it: the platform and handle parse instantly, and the share sheet asks the user for the name, which is the only field a person genuinely requires.
So a share creates a real person immediately, offline, with no triage step.

The "hasn't got a story yet" state that the research called *faded* is a property of the person (no note, no context), not a separate table - a query concern, not a state machine.

### 2. Identity: hard dedup on (platform, handle), user choice across platforms

Two different questions hide inside "is this the same person?", and they get different answers:

- **Same platform, same handle** is provably the same person. Re-sharing `instagram.com/mai.makes` must never create a twin. The save mutation dedups on it and returns an explicit outcome, per the repo's idempotent-creation convention: `{ status: "created" | "already" | "attached", personId }`.
- **A different platform** cannot be matched automatically, because a name is not a unique key and an Instagram handle has no computable relationship to a LinkedIn slug. The share sheet asks: it offers "add to <recent person>" when a parsed name matches an existing person's normalized name, plus a small search field, and defaults to creating a new person otherwise. The user decides; Haven never guesses two people are one.

**Technical constraint this exposes:** Convex indexes are over scalar fields, so an array like `contactHandles` cannot be looked up by index - there is no way to ask "which person has this Instagram handle?" without scanning the user's whole directory.
The fix is a small lookup table written in the same mutation as the array, so the two cannot drift:

```
personHandles: { userId, personId, platform, valueKey }
  .index("by_user_and_platform_and_valueKey", ["userId", "platform", "valueKey"])
  .index("by_person", ["personId"])
```

`valueKey` is the normalized handle (trimmed, lowercased, `@` stripped); normalization is deliberately naive in v1 and can grow per-platform rules later.
The array stays the display shape on the card; this table is the identity index behind it.
It is also exactly what the Phase 4 connect flow will need to answer "is this person already someone I know?".

Rules that keep the index honest:

- **Every write path that touches `contactHandles` maintains `personHandles` in the same transaction**: `addPerson` inserts rows, `editPerson` rewrites the person's rows wholesale on array replace (delete all, reinsert from the new array - the simplest correct move under the 8-handle cap), and `deletePerson` deletes the person's rows.
  Missing the delete paths would leave ghost handles that resurrect deleted people in lookups.
- **Handle identity beats user choice.** If a save arrives with `attachToPersonId` but the `(platform, valueKey)` already belongs to some person, the mutation returns `{ status: "already" }` with that existing person - it never attaches the same account to a second person. The sheet surfaces this as "you already know them".
- **No global uniqueness constraint is imposed on the legacy mutations.** `editPerson` can technically write a handle that exists on another person (free-form platforms make strict uniqueness debatable); the lookup uses `.first()` on the index and tolerates it. Tightening this later is cheap; breaking shipped mutations now is not.

### 3. The share extension is offline-only: it writes to an App Group queue and reads a local mirror

The extension does no network at all. It writes the capture into the shared App Group container, and the main app drains that queue into Convex on next launch or in the background.

Why not call Convex directly from the extension: app extensions have much tighter memory limits and are killed if they are slow to launch, the offline rule says capture must never fail at an event with dead signal, and a queue drained by the main app is simpler to make correct than sync logic living in two processes.

The non-obvious requirement: because the sheet offers "add to an existing person", the extension needs to *read* the directory, not just write to it.
So the main app maintains a small local mirror in the App Group container (person id, name, normalized name, handles) that the extension reads.
The mirror is a cache, never the source of truth, and it can be stale by days if the app has not been opened - which is why the drain defines explicit reconciliation semantics instead of trusting the mirror:

- `attachToPersonId` points at a person deleted since the mirror was written -> create a new person from the captured data instead of failing; the capture is never lost.
- The handle already exists on some person (a re-share, or a race between queue items) -> `{ status: "already" }` with that person, and **any note the user typed is appended to that person's context** (newline-separated, respecting the length cap) rather than discarded. A re-share never throws away typed input.
- Screenshots in the queue: the extension copies the image file into the App Group container and does not upload it - the main app's drain uploads the blob (`generateUploadUrl` + PUT) and calls the existing `createCapture`, so the screenshot path inherits the extraction pipeline and its blob handling unchanged, and the extension stays genuinely network-free.

## Architecture

```
Instagram / LinkedIn / X          Photos
     share profile                share screenshot
            |                          |
            +------------+-------------+
                         v
              Haven share extension
        (parse URL -> platform + handle + name guess)
        (read local mirror -> offer existing person)
        (ask: name, optional one line)
                         |
                         v
              App Group container
        queue: pending captures     mirror: people (read-only)
                         |
                         v
                   Haven main app
          drains queue -> Convex mutations
          refreshes the mirror after every sync
                         |
                         v
                      Convex
     people + personHandles + (screenshots -> existing capture pipeline)
```

## Backend work (Convex, test-first)

All additive; nothing existing changes shape.

- **`personHandles` table** plus the two indexes above, maintained by `addPerson`, `editPerson` (full rewrite on array replace), `deletePerson` (row cleanup), and the new save below, always in the same transaction as the array.
- **`saveSharedProfile` mutation**: takes `{ platform, handleValue, profileUrl, name, note?, attachToPersonId? }`.
  Dedups on `(userId, platform, valueKey)` and returns `{ status: "created" | "already" | "attached", personId }` with the reconciliation semantics above (handle identity beats attach; notes append on "already"; deleted attach target falls back to create).
  Recomputes `searchText` on every outcome - including attach, since a new handle joins the keyword haystack.
- **Slug and handle parsing** as pure functions in `src/lib.ts` (where `deriveProfileUrl` and the other URL helpers already live), unit-tested without Convex: `parseProfileUrl(url)` -> `{ platform, handle }`, and `nameGuessFromSlug(slug)` -> `"Mai Tran"` for `mai-tran-8a91b2`.
  LinkedIn slugs usually carry the person's name, which is what makes the sheet's name field prefill useful rather than empty; LinkedIn percent-encodes accented slugs and the parser decodes them, so a Vietnamese slug keeps its accents in the guess; the name field stays a confirmation rather than automation because slugs also carry id junk and abbreviations.
- **`backfillPersonHandles` internal mutation**, cursor-paged (`{ patched, isDone, cursor }`): people saved since `contactHandles` shipped have arrays but no index rows, and an unindexed person is a corrupted identity, so "done" must actually mean done.
  Operator procedure: `npx convex run people:backfillPersonHandles '{}'`, then re-run with the returned cursor until `isDone`.
- **Shipped semantics beyond the letter of this plan** (each pinned by a test):
  - `saveSharedProfile` backfills `link` from the shared URL on the "already"/"attached" paths when the person has none, and never overwrites an existing link.
  - The stored handle value has its leading `@` stripped so display and identity key share one shape.
  - Attaching a character-identical handle is an append-note no-op rather than an error.
  - An attach target already holding a different handle on that platform falls back to `created`: the drain replays the capture with nobody present to resolve the conflict, so refusing would strand it.
  - An over-cap note is clamped to what fits rather than refused, for the same reason; the existing context always survives whole, and the return carries `noteTruncated` so the drain surfaces what was cut instead of reporting a complete save.
  - A bare re-share recomputes `searchText` even when nothing else changed, healing rows written under an older formula.
  - LinkedIn country hosts (`vn.`/`uk.`/`de.`) and `/mwlite/in/` profile paths are accepted; a percent-encoded slash inside a handle segment is rejected.
  - A post URL under a handle (`x.com/<handle>/status/<id>`, `instagram.com/<user>/p/<code>`) is content, not the profile; deeper profile tabs (`/tagged`, `/in/<slug>/details`) still identify the person.
- **Drain is one mutation call per queued item, not a batch.** Queues are small (a handful of captures per event), and a batch mutation is all-or-nothing in Convex unless each item runs as a caught subtransaction - complexity with no payoff at this scale. If batching ever matters, Convex 1.41 subtransactions (`ctx.runMutation` with caught per-item rollback) are the upgrade path.
- **Orphan-sweep note**: nothing new here; screenshots drain through the existing `captures` path and its blob handling, and no new storage-id field is introduced by this plan.

## iOS work

- **Share extension target** with an App Group, activation rules for web URLs and images, and a compact SwiftUI sheet: prefilled name, one optional line ("how you met / what you talked about"), and an "add to existing person" affordance backed by the mirror.
- **Queue and mirror** in the App Group container, drained and refreshed by the main app.
- **Onboarding: the pin walkthrough.** There is no API to pin or reorder a share extension, and Haven starts buried at the end of the app row, so this has to be taught once, deliberately, the way Rodeo does it: open a real share sheet on a sample profile, walk the user through More -> Edit -> Favorites, and finish with one practice capture that lands a real person in their directory.
- **Screenshot sharing** rides the same extension, which means manual screenshot import works before the photo-library permission is ever requested.

## Milestones

1. **Backend**: `personHandles`, `saveSharedProfile`, URL/slug parsing, and the paged `backfillPersonHandles` migration (draining the queue is a client-side loop per the decision above, so there is no drain function to build).
   Done when vitest and the convex tsc check are green and a shared URL round-trips into a searchable person.
2. **Share extension, happy path**: share a profile from each of the three apps, saves offline, drains into Convex; name prefill wherever the payload allows it (LinkedIn slugs at minimum - the other two depend on the payload check in open question 1). Done when a capture made in airplane mode appears in the directory after the app is opened online.
3. **Existing-person path**: mirror, "add to existing", idempotent re-share. Done when sharing the same profile twice creates one person, and a second platform lands on the person the user picked.
4. **Onboarding walkthrough**: the pin guide plus practice capture. Done when a fresh install ends with Haven pinned in the user's share sheet and one real person saved.
5. **Enrichment, user-initiated** (later): confirm card on a person, grounded web search only, never fetching the shared profile URL.
6. **Evening follow-up** (later): the batched same-evening prompt for people saved without a note - in-app chat surface behind a communication-style notification, with the iMessage bridge as the founder's personal variant.

## Non-negotiables carried from the research

- **Never fetch the shared profile page.** The URL is a pointer, not a content source. Enrichment comes from the user's own screenshot, their own LinkedIn export, open APIs, or grounded web search behind a confirm card.
- **The one-line note lives in the share sheet**, not in a deferred session. It is the only field no machine can ever fill, and the share sheet is the moment of peak memory.
- **Capture never fails.** Offline is the design case, not the edge case.
- **No queue screens, counts, badges, or streaks.** People saved without a story fade quietly and stay searchable.

## Open questions

1. Confirm the actual share payloads from Instagram, LinkedIn, and X with a dev build (does any of them include the person's name as share text?) before finalizing the sheet.
2. iOS floor: 17 covers everything in this plan; 18 would additionally allow background voice capture from a Control or the Action Button.
3. Where voice capture attaches to this flow - inside the share sheet as an alternative to typing the note, or only in the main app.
4. Whether the legacy `platform` / `handle` fields on `people` get backfilled into `contactHandles` and `personHandles`, which is tied to the still-open decision about the orphaned web surface.
