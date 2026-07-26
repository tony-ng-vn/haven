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
  .index("by_user_platform_value", ["userId", "platform", "valueKey"])
  .index("by_person", ["personId"])
```

`valueKey` is the normalized handle (trimmed, lowercased, `@` stripped).
The array stays the display shape on the card; this table is the identity index behind it.
It is also exactly what the Phase 4 connect flow will need to answer "is this person already someone I know?".

### 3. The share extension is offline-only: it writes to an App Group queue and reads a local mirror

The extension does no network at all. It writes the capture into the shared App Group container, and the main app drains that queue into Convex on next launch or in the background.

Why not call Convex directly from the extension: app extensions have much tighter memory limits and are killed if they are slow to launch, the offline rule says capture must never fail at an event with dead signal, and a queue drained by the main app is simpler to make correct than sync logic living in two processes.

The non-obvious requirement: because the sheet offers "add to an existing person", the extension needs to *read* the directory, not just write to it.
So the main app maintains a small local mirror in the App Group container (person id, name, normalized name, handles) that the extension reads.
The mirror is a cache, never the source of truth; a queued capture referencing a person id is reconciled server-side when it drains.

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

- **`personHandles` table** plus the two indexes above, written by every path that touches `contactHandles` (`addPerson`, `editPerson`, and the new save below) so the index and the array are always written in one transaction.
- **`saveSharedProfile` mutation**: takes `{ platform, handleValue, profileUrl, name, note?, attachToPersonId? }`.
  Dedups on `(userId, platform, valueKey)` and returns `{ status, personId }`.
  With `attachToPersonId` it adds the handle to that person instead of creating one.
  Writes `searchText` like every other path, so the person is findable by keyword the moment they land.
- **Slug and handle parsing** as pure functions in `src/lib.ts` (where `deriveProfileUrl` and the other URL helpers already live), unit-tested without Convex: `parseProfileUrl(url)` -> `{ platform, handle }`, and `nameGuessFromSlug(slug)` -> `"Mai Tran"` for `mai-tran-8a91b2`.
  LinkedIn slugs usually carry the person's name, which is what makes the sheet's name field prefill useful rather than empty.
- **Batch drain mutation** so the main app can flush several queued captures in one round trip, each returning its own status.
- **Orphan-sweep note**: nothing new here yet; screenshots shared into Haven reuse the existing `captures` path and its blob handling.

## iOS work

- **Share extension target** with an App Group, activation rules for web URLs and images, and a compact SwiftUI sheet: prefilled name, one optional line ("how you met / what you talked about"), and an "add to existing person" affordance backed by the mirror.
- **Queue and mirror** in the App Group container, drained and refreshed by the main app.
- **Onboarding: the pin walkthrough.** There is no API to pin or reorder a share extension, and Haven starts buried at the end of the app row, so this has to be taught once, deliberately, the way Rodeo does it: open a real share sheet on a sample profile, walk the user through More -> Edit -> Favorites, and finish with one practice capture that lands a real person in their directory.
- **Screenshot sharing** rides the same extension, which means manual screenshot import works before the photo-library permission is ever requested.

## Milestones

1. **Backend**: `personHandles`, `saveSharedProfile`, URL/slug parsing, batch drain. Done when vitest and the convex tsc check are green and a shared URL round-trips into a searchable person.
2. **Share extension, happy path**: share a profile from each of the three apps, name prefilled, saves offline, drains into Convex. Done when a capture made in airplane mode appears in the directory after the app is opened online.
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
