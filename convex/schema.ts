import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

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
    screenshotId: v.optional(v.id("_storage")),
    // Euno Meet provenance. Each side still gets a private people row; this
    // key only lets a repeat in-person exchange stay idempotent.
    eunoContactUserId: v.optional(v.string()),
    // Semantic search. embeddedText doubles as the idempotency key so the
    // embed action can skip recomputing an unchanged person.
    embedding: v.optional(v.array(v.float64())),
    embeddedText: v.optional(v.string()),
  })
    .index("by_user", ["userId"])
    .index("by_user_and_eunoContactUserId", ["userId", "eunoContactUserId"])
    // Same reasoning as captures.by_screenshotId: the orphaned-upload sweep
    // needs a sound, bounded way to check "is this blob referenced?".
    .index("by_screenshotId", ["screenshotId"])
    .searchIndex("search_normalized_name", {
      searchField: "normalizedName",
      filterFields: ["userId"],
    })
    .vectorIndex("by_embedding", {
      vectorField: "embedding",
      dimensions: 1536,
      filterFields: ["userId"],
    }),
  // A future mutual-link flow should create one row only after both Euno users
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

  // A user's public-in-the-moment Euno handle. This is not a social profile:
  // it exists only so two people standing together can intentionally exchange.
  profiles: defineTable({
    userId: v.string(),
    username: v.string(),
    updatedAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_username", ["username"]),

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
  waitlist: defineTable({
    email: v.string(),
    source: v.union(v.literal("desktop"), v.literal("phone")),
  }).index("by_email", ["email"]),
});
