import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  people: defineTable({
    // Clerk's identity.tokenIdentifier ("issuer|subject"); the stable
    // ownership key now that there is no local users table.
    userId: v.string(),
    name: v.string(),
    link: v.optional(v.string()),
    context: v.optional(v.string()),
    updatedAt: v.number(),
    // Captured-from-screenshot provenance; all optional so hand-added
    // people need no migration.
    platform: v.optional(v.string()),
    handle: v.optional(v.string()),
    headline: v.optional(v.string()),
    screenshotId: v.optional(v.id("_storage")),
    // Semantic search. embeddedText doubles as the idempotency key so the
    // embed action can skip recomputing an unchanged person.
    embedding: v.optional(v.array(v.float64())),
    embeddedText: v.optional(v.string()),
  })
    .index("by_user", ["userId"])
    .searchIndex("search_name", {
      searchField: "name",
      filterFields: ["userId"],
    })
    .vectorIndex("by_embedding", {
      vectorField: "embedding",
      dimensions: 1536,
      filterFields: ["userId"],
    }),
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
    error: v.optional(v.string()),
  }).index("by_user", ["userId"]),
});
