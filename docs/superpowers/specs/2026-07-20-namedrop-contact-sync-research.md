# NameDrop-Style Contact Sync Research

Date: 2026-07-20
Status: Implemented MVP

## Product idea

Euno Meet is a small in-person exchange affordance on the atlas. One person taps
Meet, enters or speaks the other person's Euno username, verifies the lookup, and
taps one confirmation. Euno then creates private `people` rows for both sides.

This borrows the spirit of Apple NameDrop without copying the transport:
intentional, mutual, ephemeral, and useful only when two people are together. It
is not discovery, followers, a feed, or a public social graph.

## Decision: instant mutual with confirmation

The MVP uses instant mutual exchange with a local confirmation, not
request-and-accept.

Rationale:

- The in-person setting already provides the second-party confirmation: the
  other person says or shows their username.
- A pending-invite inbox would add social-network surface area and notification
  semantics before the core exchange is proven.
- Convex can create both private rows in one mutation, keeping the operation
  atomic and easy to reason about.

Failure mode: if a username is entered by mistake, each person can delete the
private contact row later. The MVP does not expose contact lists or activity to
anyone else.

## Data model

### `profiles`

One row per signed-in user:

- `userId`: Clerk `identity.tokenIdentifier`, derived server-side via
  `requireUser`.
- `username`: normalized lowercase handle, unique by indexed lookup.
- `updatedAt`: timestamp for profile edits.

Indexes:

- `by_user` for the signed-in user's own profile.
- `by_username` for exact username lookup.

### `people`

Meet still writes ordinary private `people` rows. The only schema addition is:

- `eunoContactUserId`: optional Clerk tokenIdentifier for the profile that was
  exchanged. It makes repeat exchanges idempotent.

Meet-created rows use:

- `name`: `@username`
- `platform`: `Euno`
- `handle`: username
- `context`: `Met in person through Euno Meet.`

Each side owns its own row. No query returns another user's private row.

## Backend API

`convex/profiles.ts`:

- `getMyProfile()`: returns the caller's username profile or `null`.
- `setUsername(username)`: validates, normalizes, and claims/updates a unique
  username for the caller.
- `lookupByUsername(username)`: authenticated exact lookup returning only public
  username data.
- `meetExchange(username)`: requires the caller to have a profile, rejects
  self-exchange, looks up the peer, then creates one private `people` row for
  each side if missing.

All functions derive identity with `requireUser`; no user id is accepted from
the client for authorization.

## UI

The atlas gets a small `Meet` widget. Opening it shows a quiet glass sheet:

1. If the caller has no username, first choose one.
2. Enter the other person's username.
3. Optionally use Web Speech API when available to fill the username field.
4. Confirm exchange.
5. Optionally open the newly created private contact.

The sheet is deliberately small and transient. It uses existing atlas glass
language, neutral text, and one confirmation action; no purple glow, no hero
marketing card, no social-network chrome.

## Tests

Focused Convex tests cover:

- username normalization and ownership
- username uniqueness across users
- authenticated-only access
- public lookup projection
- mutual private `people` row creation
- idempotent repeated exchange
- self-profile and self-exchange rejection

## Out of scope

- Love-alarm geolocation/proximity.
- Background contact import or Apple Contacts sync.
- Public profiles, follower graphs, feeds, or username search directory.
- Shared notes / CRDT collaboration.
- Pending invite inbox or notifications.
