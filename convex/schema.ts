import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import {
  cityInputValidator,
  cityValidator,
  handleValidator,
  onboardingValidator,
  platformValidator,
} from "./profileFields";
import { contactHandleValidator } from "./peopleFields";

export default defineSchema({
  people: defineTable({
    // Clerk's identity.tokenIdentifier ("issuer|subject"); the stable
    // ownership key now that there is no local users table.
    userId: v.string(),
    name: v.string(),
    // Accent-insensitive lowercase key for search_normalized_name; see
    // nameSearch.ts. Optional because rows created before this field
    // existed (and rows captures.ts inserts directly) need a backfill --
    // see backfillNormalizedNames in people.ts.
    normalizedName: v.optional(v.string()),
    link: v.optional(v.string()),
    context: v.optional(v.string()),
    updatedAt: v.number(),
    // Captured-from-screenshot provenance; all optional so hand-added
    // people need no migration.
    platform: v.optional(v.string()),
    handle: v.optional(v.string()),
    headline: v.optional(v.string()),
    // The profile's own about text, kept from extraction because it is the
    // words a "who do I know who does X" query is most likely to paraphrase.
    bio: v.optional(v.string()),
    screenshotId: v.optional(v.id("_storage")),
    // Haven Meet provenance. Each side still gets a private people row; this
    // key only lets a repeat in-person exchange stay idempotent.
    havenContactUserId: v.optional(v.string()),
    // Structured attributes for the MVP search contract: the display value
    // and its accent-folded filter key travel together, because the Phase 3
    // chips equality-match on the key (normalizeName in nameSearch.ts) while
    // the UI shows what the user actually typed.
    city: v.optional(cityInputValidator),
    cityKey: v.optional(v.string()),
    company: v.optional(v.string()),
    companyKey: v.optional(v.string()),
    role: v.optional(v.string()),
    roleKey: v.optional(v.string()),
    // A photo the user attached to this person, distinct from the capture
    // screenshot above: the screenshot is provenance, the photo is the face.
    photoStorageId: v.optional(v.id("_storage")),
    // Bounded, not unbounded: the mutations cap the list at 8 entries with
    // one handle per platform, so this array can never grow past that.
    contactHandles: v.optional(v.array(contactHandleValidator)),
    // Must name a platform present in contactHandles; removing that handle
    // clears the pointer (enforced in people.ts, same invariant as
    // profiles.primaryPlatform).
    preferredPlatform: v.optional(v.string()),
    // Semantic search. embeddedText doubles as the idempotency key so the
    // embed action can skip recomputing an unchanged person.
    embedding: v.optional(v.array(v.float64())),
    embeddedText: v.optional(v.string()),
    // Keyword haystack for search_text, pre-folded by personSearchText in
    // nameSearch.ts. Optional because legacy rows need a backfill -- same
    // reasoning as normalizedName above; see backfillSearchText.
    searchText: v.optional(v.string()),
  })
    .index("by_user", ["userId"])
    // The Directory screen pages most-recently-touched first.
    .index("by_user_and_updatedAt", ["userId", "updatedAt"])
    .index("by_user_and_havenContactUserId", ["userId", "havenContactUserId"])
    // Same reasoning as captures.by_screenshotId: the orphaned-upload sweep
    // needs a sound, bounded way to check "is this blob referenced?".
    .index("by_screenshotId", ["screenshotId"])
    .index("by_photoStorageId", ["photoStorageId"])
    // Chip-only searches (no keyword) range on one of these; a keyword
    // search reaches the same chips through search_text's filterFields.
    .index("by_user_and_companyKey", ["userId", "companyKey"])
    .index("by_user_and_cityKey", ["userId", "cityKey"])
    .index("by_user_and_roleKey", ["userId", "roleKey"])
    .searchIndex("search_normalized_name", {
      searchField: "normalizedName",
      filterFields: ["userId"],
    })
    .searchIndex("search_text", {
      searchField: "searchText",
      filterFields: ["userId", "companyKey", "cityKey", "roleKey"],
    })
    .vectorIndex("by_embedding", {
      vectorField: "embedding",
      dimensions: 1536,
      filterFields: ["userId"],
    }),
  // One line of what the user wrote about a person, kept as its own row with
  // its own vector. people.context stays the rolled-up display copy; these
  // are the retrieval copy, because a single averaged person vector scores
  // low for a query that hits only one facet of a well-known person.
  // Derived, never authored directly: every write path that sets a person's
  // context syncs these in the same transaction (syncMemories in
  // memories.ts), and deletePerson takes them with it.
  memories: defineTable({
    userId: v.string(),
    personId: v.id("people"),
    text: v.string(),
    // The person's updatedAt when the line was first seen, so a migrated
    // memory dates from when the user wrote it, not from the migration.
    createdAt: v.number(),
    // Same idempotency contract as people.embedding/embeddedText: the stored
    // text is the key for the stored vector.
    embedding: v.optional(v.array(v.float64())),
    embeddedText: v.optional(v.string()),
  })
    .index("by_person", ["personId"])
    .vectorIndex("by_embedding", {
      vectorField: "embedding",
      dimensions: 1536,
      filterFields: ["userId"],
    }),
  // The identity index behind people.contactHandles: Convex indexes scalar
  // fields only, so "which person has this Instagram handle?" is unanswerable
  // from the array itself. Every write that touches contactHandles maintains
  // these rows in the same transaction, or the two drift -- see people.ts.
  // valueKey is the handle trimmed, stripped of leading "@", and lowercased.
  personHandles: defineTable({
    userId: v.string(),
    personId: v.id("people"),
    platform: v.string(),
    valueKey: v.string(),
  })
    .index("by_user_and_platform_and_valueKey", [
      "userId",
      "platform",
      "valueKey",
    ])
    .index("by_person", ["personId"]),
  // A future mutual-link flow should create one row only after both Haven users
  // have explicitly connected. Each side binds the relationship to their own
  // private person row; the shared-note API uses this as its access gate.
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
  }).index("by_connectionId", ["connectionId"]),
  // A screenshot waiting to be triaged into a person. Deleted on accept
  // (the file moves to the person) or discard (the file is deleted too).
  captures: defineTable({
    userId: v.string(),
    screenshotId: v.id("_storage"),
    status: v.union(
      v.literal("pending"),
      v.literal("ready"),
      v.literal("failed"),
    ),
    extracted: v.optional(
      v.object({
        platform: v.string(),
        name: v.string(),
        handle: v.optional(v.string()),
        headline: v.optional(v.string()),
        bio: v.optional(v.string()),
      }),
    ),
    // Short, generic, user-safe message. Never the raw upstream text.
    error: v.optional(v.string()),
    // Raw upstream/error text for our own debugging. Never returned to a
    // client -- listCaptures and getCapture must not project this field.
    errorDetail: v.optional(v.string()),
  })
    .index("by_user", ["userId"])
    // Lets the stuck-pending sweep find old "pending" rows without a table
    // scan; Convex appends _creationTime as the trailing key, so this index
    // also supports the age cutoff range on the same query.
    .index("by_status", ["status"])
    // Lets the orphaned-upload sweep check "is this blob referenced?" as an
    // exact indexed lookup per candidate instead of a bounded table scan --
    // see sweepOrphanedUploads in captures.ts for why that matters for
    // soundness.
    .index("by_screenshotId", ["screenshotId"]),
  // Fixed-window per-user rate limiting. One row per (userId, action) pair;
  // an action name like "createCapture:minute" models one window, so a
  // function with two windows (e.g. per-minute and per-day) gets two rows.
  rateLimits: defineTable({
    userId: v.string(),
    action: v.string(),
    windowStart: v.number(),
    count: v.number(),
  }).index("by_user_action", ["userId", "action"]),

  // A user's own Haven card. `username` is the one handle the product has:
  // the legacy web meet-exchange claims it via setUsername and the beacon QR
  // encodes it as inhavens.com/<username>. Everything below it is the Phase 1
  // card, all optional so rows claimed by the legacy flow stay valid with no
  // backfill.
  profiles: defineTable({
    userId: v.string(),
    username: v.string(),
    updatedAt: v.number(),
    name: v.optional(v.string()),
    photoStorageId: v.optional(v.id("_storage")),
    city: v.optional(cityValidator),
    // Bounded, not unbounded: updateMyProfile allows one handle per platform,
    // so this array can never hold more than four entries.
    handles: v.optional(v.array(handleValidator)),
    primaryPlatform: v.optional(platformValidator),
    // Edit-only fields; never asked during onboarding, filtered on in Phase 3.
    company: v.optional(v.string()),
    role: v.optional(v.string()),
    // What happened to each onboarding question. Separate from the fields
    // above because a skip is not a fact about the card: a declined city and
    // a city nobody was asked for leave the same empty field, and only this
    // tells them apart. Optional, so every row written before it existed
    // stays valid.
    onboarding: v.optional(onboardingValidator),
  })
    .index("by_user", ["userId"])
    .index("by_username", ["username"])
    // The orphan sweep needs this to see that a photo is still in use.
    // Without it a profile photo reads as unreferenced and gets deleted.
    .index("by_photoStorageId", ["photoStorageId"]),

  // Opt-in, short-lived proximity sessions for Love Alarm. Kept separate from
  // people because heartbeats are intentionally high-churn operational data.
  loveAlarmPresence: defineTable({
    userId: v.string(),
    roomCode: v.string(),
    displayName: v.string(),
    joinedAt: v.number(),
    lastSeenAt: v.number(),
    expiresAt: v.number(),
  })
    .index("by_userId_and_roomCode", ["userId", "roomCode"])
    .index("by_userId_and_expiresAt", ["userId", "expiresAt"])
    .index("by_roomCode_and_expiresAt", ["roomCode", "expiresAt"]),

  // Cursor state for paginated background sweeps: without a persisted
  // watermark a bounded sweep re-reads the same head of the table forever
  // and never progresses past rows it must skip.
  sweepState: defineTable({
    key: v.string(),
    watermark: v.number(),
  }).index("by_key", ["key"]),

  // Public waitlist signups from the /#/join landing. No auth: these are
  // strangers, not users. Email is stored normalized (trimmed + lowercased)
  // so by_email gives an exact dedupe lookup. `source` records which
  // responsive layout they joined from. _creationTime is the signup time.
  // `name` is required by the joinWaitlist mutation for every new signup, but
  // stays optional in the schema because rows created before this field
  // existed have none -- same reasoning as people.normalizedName above.
  waitlist: defineTable({
    name: v.optional(v.string()),
    email: v.string(),
    source: v.union(v.literal("desktop"), v.literal("phone")),
  }).index("by_email", ["email"]),
});
