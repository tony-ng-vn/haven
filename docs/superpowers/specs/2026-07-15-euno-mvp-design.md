# Euno MVP Design

Date: 2026-07-15
Status: Approved for planning

## Problem

It is hard to store relationships with social media and contacts.
A relationship cannot be captured by data plus a friend list.
And there is no effective way to use that information for searching -- to refind a person from what you remember.

## Product statement

Relationships are not binary (friend vs not friend).
Social media and contacts only help with the first step (the initial connect), not with maintaining the relationship over time.
Euno is the maintenance layer: a personal memory layer over the people of your life.

The one and only goal is to help people maintain connection with everyone they connect with.
Euno does not judge how well someone knows someone -- there is no health score, no ranking, no scoring of closeness.

The way Euno delivers this is as a search layer to find back the people you met in life.
You bring a fragment of memory; Euno gives you back the person, so you can reach out and keep the connection alive.

## MVP scope

The one loop we are building:

1. Login.
2. Search a contact, or add a new one.
3. Add info: an optional link plus any context the user wants to remember about that person.
4. Save.
5. Return to step 2.

### In scope

- Convex-backed login via the Convex Auth Password provider (email + password, no external email service to configure).
- Add a person by hand (name).
- Search people by name, live as you type.
- Edit a person's link and context, and save.
- Per-user data isolation (everything scoped to the logged-in user).

### Explicitly out of scope for the MVP

- Apple Contacts or any bulk import.
- Delete person.
- Fuzzy or semantic search (name prefix search only).
- Append-only note history (context is a single editable field for now).
- Mobile app, iMessage transport, event capture.

## Architecture

A fresh standalone project at `Euno/euno-app`, its own git repo. Two parts:

1. Convex backend -- owns auth, the database, and query/mutation functions. No separate server process to run or deploy.
2. Vite + React frontend -- the screens.

Stack: TypeScript, Convex, Convex Auth, Vite, React 19, Vitest for tests.
This mirrors the proven stack already used by the Friendy project in this repo, so nothing is exotic.

### Why Convex

Convex bundles auth, database, reactive queries, and backend functions into one system.
For a login + CRUD + search loop it is less to build than a hand-rolled server plus database plus auth, and the frontend gets live-updating query results for free.

## Data model

Two tables.

### `users`

Provided by Convex Auth. We do not hand-roll auth or user records.

### `people`

| Field       | Type                | Notes                                              |
| ----------- | ------------------- | -------------------------------------------------- |
| `userId`    | Id<"users">         | Owner. Every query filters by this.                |
| `name`      | string              | Required. What you type to add and to search.      |
| `link`      | string (optional)   | Optional URL (LinkedIn, site, socials).            |
| `context`   | string (optional)   | Free text -- what you want to remember about them. |
| `createdAt` | number              | ms timestamp. First seed of "when did we connect". |
| `updatedAt` | number              | ms timestamp. First seed of "last touched".        |

Indexes:

- `by_user` on `["userId"]` -- list/scope a user's people.
- A search index on `name` filtered by `userId` -- powers live search in step 2.

`link` and `context` live directly on the person for the MVP (no separate notes table).
Saving again updates them in place.

Design note: `createdAt` / `updatedAt` support recency ordering (for example, showing recently added or recently touched people when the search box is empty). They are not a health or closeness score, and Euno does not rank relationships.

## Backend functions (Convex)

All functions require an authenticated user and operate only on that user's rows.

- `searchPeople(query: string): Person[]`
  Live name search for step 2. Empty query returns the user's recent people so the screen is never blank.
- `addPerson(name: string): Id`
  Creates a person with just a name; sets `createdAt` / `updatedAt`. Returns the new id so the UI can open the detail screen.
- `getPerson(id): Person`
  Fetches one person for the detail screen. Rejects if the person is not owned by the caller.
- `updatePerson(id, { link?, context? })`
  Saves link and context; bumps `updatedAt`. Rejects if not owned by the caller.

Ownership checks live in every read and write. A user can never read or mutate another user's person.

## Screens (frontend)

Three screens, matching the loop.

1. Login screen
   Convex Auth Password provider (sign up / sign in with email + password). Shown when logged out; the rest of the app is gated behind it.

2. Search / Add screen (steps 2 and 5)
   A search box. Typing runs `searchPeople` live.
   - Matches render as a tappable list; tapping opens the person detail screen.
   - When nothing matches, an "Add <typed name>" button calls `addPerson`, then opens the new person's detail screen.
   This is also the screen the loop returns to after a save.

3. Person detail screen (steps 3 and 4)
   Shows the name, an optional link input, and a context text area.
   Save calls `updatePerson`, then routes back to the Search / Add screen.

## Design direction

The UI is inspired by Apple's design language (Human Interface Guidelines). The point is not to copy Apple, but to make Euno feel calm, focused, and content-first -- fitting for a tool whose whole job is to quietly hand you back a person.

Principles to follow:

- Clarity: content leads, chrome recedes. One primary action per screen. The search box and the person are the heroes; everything else is quiet.
- Deference: generous whitespace, restrained color, a single subtle accent. No heavy borders or loud UI. Let the layout breathe.
- Depth: soft, layered surfaces -- gentle shadows, translucency/blur for overlays, large corner radii on cards and inputs.
- Typography: the system font stack (SF Pro on Apple devices via `-apple-system`), a clear type scale, comfortable line-height, real hierarchy from size and weight rather than boxes and rules.
- Motion: short, natural, spring-like transitions (screen changes, list item taps). Nothing bouncy or attention-seeking. Respect `prefers-reduced-motion`.
- Light and dark: support both, following the system preference.
- Touch/click targets are large and forgiving; controls have soft pressed states.

This direction guides the frontend build. Concrete component and layout design happens during implementation (the frontend-design skill), grounded in these principles.

## Error handling

- Unauthenticated access to any screen but login -> redirect to login.
- Backend functions reject reads/writes on people the caller does not own.
- Adding a person with an empty/whitespace name is blocked in the UI and rejected server-side.
- Save with no changes is a no-op that still returns to the search screen (no error).

## Testing

- Convex function tests (Vitest): ownership isolation (user A cannot read/update user B's person), add creates with timestamps, update bumps `updatedAt`, search matches by name prefix and excludes other users' people.
- A thin end-to-end check of the loop: add -> appears in search -> open -> save context -> reopen shows saved context.

## Future (not now, but the model allows it)

- Apple Contacts import to seed the back catalog.
- Append-only note history instead of a single context field.
- Semantic / fuzzy search over context, not just name.
