# Mutual note syncing between two people

## Problem

Euno is currently a private personal memory layer: each `people` row belongs to
one Clerk identity (`identity.tokenIdentifier`) and `people.context` is the
owner's private memory. The product owner wants a narrow multi-user surface that
does not turn Euno into messaging, a feed, or social media.

The product opportunity: when two Euno users have intentionally connected, they
can maintain one shared memory of the relationship. This is not a chat log and
not a replacement for private notes. It is a pair-scoped note that both people
can edit, sitting beside each person's private context.

Non-goals:

- Do not share or mirror `people.context`.
- Do not introduce feeds, likes, presence, read receipts, typing indicators, or
  chat-style message streams.
- Do not implement love-alarm or NameDrop exchange flows.

## Data model options

### Option A: Shared field on both `people` rows

Add `sharedContext` to each user's private `people` row and keep the two copies
in sync.

Pros:

- Easy to render on `PersonDetail`.
- Keeps all visible person memory near the person row.

Cons:

- Blurs the boundary between owner-private memory and pair-shared memory.
- Requires dual writes and conflict handling across two documents.
- Makes access control harder because a private row would contain data owned by
  another user too.

Verdict: reject. It violates the core privacy model.

### Option B: One pair-scoped shared note document

Create a mutual `connections` row for the two users and a separate `sharedNotes`
row keyed by that connection.

Pros:

- Private `people.context` stays owner-only.
- One canonical shared note, no dual-copy drift.
- Access checks can be expressed as: current user owns this person row, and this
  person row is bound to a connected pair.
- Fits Convex subscriptions well: both users subscribe to the same small doc.

Cons:

- Requires a connection/mutual-link concept before the note is usable.
- Needs a future connection creation flow to bind each user's private person row.

Verdict: recommended MVP.

### Option C: Append-only shared memory entries

Create a `sharedNoteEntries` table where each edit appends a dated memory item.

Pros:

- Natural audit/history.
- Avoids overwrite conflicts.

Cons:

- Reads like a feed or chat transcript unless aggressively designed otherwise.
- More UI surface and more data lifecycle questions.
- Requires pagination and moderation/deletion semantics sooner.

Verdict: useful later for history, not the first shared memory MVP.

## Minimal mutual-link requirement

The shared-note API needs one row that proves both users are connected and maps
the pair to each side's private person row:

```ts
connections: {
  userAId: string; // Clerk tokenIdentifier
  userBId: string; // Clerk tokenIdentifier
  personAId: Id<"people">; // owned by userAId
  personBId: Id<"people">; // owned by userBId
  status: "connected";
  createdAt: number;
  updatedAt: number;
}
```

Indexes:

- `by_userAId_and_personAId`
- `by_userBId_and_personBId`
- `by_userAId_and_userBId`

The future connection creation flow should enforce a canonical pair order
(`userAId < userBId`) and create exactly one row per pair. The current shared
note implementation assumes that flow exists and gates on this table; it does
not implement discovery, invitations, or contact exchange.

## Sync semantics

### CRDT

CRDT text editing would allow concurrent character-level merges.

Pros:

- Best for simultaneous collaborative editing.
- Avoids overwrite conflicts.

Cons:

- Heavy for a calm memory note.
- Requires client-side editor state, storage format decisions, and conflict UX.
- Implies "live collaboration," which risks a productivity/chat vibe.

Verdict: not MVP.

### Last-write-wins single note

Store one `content` value on `sharedNotes`, patch it on save, and record
`updatedAt`/`updatedByUserId`.

Pros:

- Smallest conceptual model.
- Calm: one note, one save action.
- Works with Convex's reactive queries immediately.

Cons:

- A stale save can overwrite the other user's recent edit.
- No history.

Verdict: recommended MVP, with copy that avoids implying real-time co-editing.
If conflict risk becomes visible, add a compare-on-save `baseUpdatedAt` guard
before considering CRDT.

### Append-only entries

Each save appends an entry; the UI composes entries into a memory timeline or
latest note.

Pros:

- Never overwrites.
- Natural audit trail.

Cons:

- Timeline presentation feels feed-like.
- Requires deletion/edit policy.

Verdict: defer.

## Recommended MVP

Implement one pair-scoped note:

- `people.context` remains private and unchanged.
- `connections` gates access and binds the current private person row to the
  other user's private person row.
- `sharedNotes` stores one optional `content` field per connection.
- Reads return `null` when the current user is not connected for that person.
- Writes reject when there is no mutual connection.
- Empty content clears the note content without touching private context.
- Length cap matches private context at 4000 characters.

This gives the product owner a working seam for future connected-user features
without broadening Euno into a social network.

## Schema and API

Implemented schema:

```ts
connections: defineTable({
  userAId: v.string(),
  userBId: v.string(),
  personAId: v.id("people"),
  personBId: v.id("people"),
  status: v.literal("connected"),
  createdAt: v.number(),
  updatedAt: v.number(),
})
  .index("by_userAId_and_personAId", ["userAId", "personAId"])
  .index("by_userBId_and_personBId", ["userBId", "personBId"])
  .index("by_userAId_and_userBId", ["userAId", "userBId"]),

sharedNotes: defineTable({
  connectionId: v.id("connections"),
  content: v.optional(v.string()),
  updatedAt: v.number(),
  updatedByUserId: v.string(),
}).index("by_connectionId", ["connectionId"])
```

Implemented Convex functions:

- `sharedNotes.getForPerson({ personId })`
  - derives the caller with `requireUser`
  - verifies the caller owns `personId`
  - resolves a connected pair row by side-specific indexes
  - returns `null` when no mutual connection exists
  - returns `{ connectionId, content?, updatedAt?, updatedByMe }` when connected
- `sharedNotes.updateForPerson({ personId, content? })`
  - derives the caller with `requireUser`
  - rate-limits writes
  - verifies the mutual connection gate
  - trims and length-caps content
  - inserts or patches the one shared note for the connection

Future API checklist:

- Add a connection creation/invitation flow that canonicalizes pair order and
  proves both users consented.
- Add a unique-pair invariant in the creation function.
- Consider `baseUpdatedAt` optimistic conflict detection if overwrite reports
  appear.
- Decide whether disconnecting hides, freezes, or deletes `sharedNotes`.
- Add a connection audit/history table only if privacy review requires it.

## UI placement

`PersonDetail` should continue to lead with the person's identity, link, and
private context. Shared notes belong below the private context and save action,
above removal/destructive controls.

Current UI stub:

- Renames the existing textarea label to "Private context".
- Adds a separate "Shared notes" card.
- If no mutual connection exists, the card says the shared space is available
  after both people connect in Euno.
- If connected, the card shows a single textarea and a quiet save action.
- Status copy says whether the shared note was last updated by the current user
  or the other person; no timestamps, presence, typing, read receipts, badges,
  or notification hooks.

This keeps the feature in the memory register, not the messaging register.

## Privacy

- `people.context` stays owner-only and is never copied into `sharedNotes`.
- Every shared-note function derives identity server-side through Clerk
  `tokenIdentifier` via `requireUser`; no user id is accepted from the client.
- A user can only access a shared note through their own private `people` row.
- The connection row must bind both sides to person rows owned by the expected
  users; stale or mismatched person rows fail the gate.
- Search/embeddings continue to use private `people` data only. Shared notes are
  not embedded or surfaced in search in this MVP.
- Disconnect semantics need an explicit product decision before launch. The
  safest default is to hide shared notes from both users after disconnect while
  retaining data for a short recovery window, then delete on a retention policy.
