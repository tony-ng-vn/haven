import {
  action,
  internalAction,
  internalMutation,
  internalQuery,
  mutation,
  query,
  ActionCtx,
} from "./_generated/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import { buildEmbedText } from "../src/lib";
import { embedText } from "./openaiClient";
import { requireUser } from "./authz";
import { checkRateLimit } from "./rateLimit";
import { normalizeName } from "./nameSearch";

// Bound every list read so the query stays scalable as the table grows.
const RESULT_LIMIT = 20;

// Semantic matches below this cosine similarity read as noise, not memory.
// Tuned against real data during verification.
const MIN_SEMANTIC_SCORE = 0.3;

const MINUTE_MS = 60_000;

// Keeps a single wildly long paste from bloating a document or dominating
// its own embedding.
const MAX_CONTEXT_LENGTH = 4000;
const CONTEXT_TOO_LONG_ERROR =
  "Context is too long -- keep it under 4000 characters";

// The embeddings request has its own size ceiling; slicing here means an
// over-long stored context can never fail the whole embed call.
const MAX_EMBED_INPUT_LENGTH = 8000;

// Batch size for the maintenance mutations below, kept well under Convex's
// per-transaction document limits.
const BACKFILL_BATCH_SIZE = 500;

// Backoff schedule for the embed action: index 0 is the delay before retry
// attempt 1, index 1 before attempt 2. After that we give up.
const EMBED_RETRY_DELAYS_MS = [30_000, 5 * 60_000];

// What the client is ever allowed to see for a person. Never embedding,
// embeddedText, or userId -- those stay server-side.
const personValidator = v.object({
  _id: v.id("people"),
  _creationTime: v.number(),
  name: v.string(),
  link: v.optional(v.string()),
  context: v.optional(v.string()),
  platform: v.optional(v.string()),
  handle: v.optional(v.string()),
  headline: v.optional(v.string()),
  screenshotId: v.optional(v.id("_storage")),
  updatedAt: v.number(),
});

function projectPerson(person: Doc<"people">) {
  return {
    _id: person._id,
    _creationTime: person._creationTime,
    name: person.name,
    link: person.link,
    context: person.context,
    platform: person.platform,
    handle: person.handle,
    headline: person.headline,
    screenshotId: person.screenshotId,
    updatedAt: person.updatedAt,
  };
}

export const addPerson = mutation({
  args: { name: v.string(), context: v.optional(v.string()) },
  returns: v.id("people"),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "addPerson", 30, MINUTE_MS);
    const name = args.name.trim();
    if (name === "") {
      throw new Error("Name is required");
    }
    if (args.context !== undefined && args.context.length > MAX_CONTEXT_LENGTH) {
      throw new Error(CONTEXT_TOO_LONG_ERROR);
    }
    const personId = await ctx.db.insert("people", {
      userId,
      name,
      normalizedName: normalizeName(name),
      context: args.context,
      updatedAt: Date.now(),
    });
    await ctx.scheduler.runAfter(0, internal.people.embed, { personId });
    return personId;
  },
});

export const searchPeople = query({
  args: { query: v.string() },
  returns: v.array(personValidator),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    // A query of only combining marks/punctuation can normalize to "" --
    // treat that the same as an empty query rather than search for "".
    const normalizedTerm = normalizeName(args.query);
    const people =
      normalizedTerm === ""
        ? await ctx.db
            .query("people")
            .withIndex("by_user", (q) => q.eq("userId", userId))
            .order("desc")
            .take(RESULT_LIMIT)
        : await ctx.db
            .query("people")
            .withSearchIndex("search_normalized_name", (q) =>
              q.search("normalizedName", normalizedTerm).eq("userId", userId),
            )
            .take(RESULT_LIMIT);
    return people.map(projectPerson);
  },
});

export const getPerson = query({
  args: { id: v.id("people") },
  returns: v.union(v.null(), personValidator),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const person = await ctx.db.get("people", args.id);
    if (person === null || person.userId !== userId) {
      return null;
    }
    return projectPerson(person);
  },
});

export const updatePerson = mutation({
  args: {
    id: v.id("people"),
    link: v.optional(v.string()),
    context: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "updatePerson", 60, MINUTE_MS);
    const person = await ctx.db.get("people", args.id);
    if (person === null || person.userId !== userId) {
      throw new Error("Person not found");
    }
    if (args.context !== undefined && args.context.length > MAX_CONTEXT_LENGTH) {
      throw new Error(CONTEXT_TOO_LONG_ERROR);
    }
    // The detail screen always sends both fields; an omitted (undefined) value
    // means the user cleared that input, so patch unsets the field on purpose.
    // Callers that want to leave a field untouched must resend its current value.
    // updatePerson never takes a name, so normalizedName (set at insert) is
    // never stale here and does not need recomputing.
    await ctx.db.patch("people", args.id, {
      link: args.link,
      context: args.context,
      updatedAt: Date.now(),
    });
    await ctx.scheduler.runAfter(0, internal.people.embed, {
      personId: args.id,
    });
    return null;
  },
});

export const deletePerson = mutation({
  args: { personId: v.id("people") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const person = await ctx.db.get("people", args.personId);
    if (person === null || person.userId !== userId) {
      throw new Error("Person not found");
    }
    if (person.screenshotId !== undefined) {
      await ctx.storage.delete(person.screenshotId);
    }
    await ctx.db.delete("people", args.personId);
    return null;
  },
});

// ------------------------------------------------------------- embeddings

export const getPersonInternal = internalQuery({
  args: { id: v.id("people") },
  handler: async (ctx, args) => {
    return await ctx.db.get("people", args.id);
  },
});

export const saveEmbedding = internalMutation({
  args: {
    id: v.id("people"),
    embedding: v.array(v.float64()),
    embeddedText: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const person = await ctx.db.get("people", args.id);
    if (person === null) {
      return null;
    }
    await ctx.db.patch("people", args.id, {
      embedding: args.embedding,
      embeddedText: args.embeddedText,
    });
    return null;
  },
});

// Shared by the embed action and the backfill (guidelines: do not call an
// action from an action in the same runtime; share a helper instead).
async function embedPerson(
  ctx: ActionCtx,
  personId: Id<"people">,
): Promise<void> {
  const person: Doc<"people"> | null = await ctx.runQuery(
    internal.people.getPersonInternal,
    { id: personId },
  );
  if (person === null) {
    return;
  }
  const text = buildEmbedText({
    name: person.name,
    platform: person.platform,
    handle: person.handle,
    headline: person.headline,
    context: person.context,
  }).slice(0, MAX_EMBED_INPUT_LENGTH);
  // Idempotent: the stored (sliced) text is the key for the stored vector.
  if (person.embedding !== undefined && person.embeddedText === text) {
    return;
  }
  const embedding = await embedText(text);
  await ctx.runMutation(internal.people.saveEmbedding, {
    id: personId,
    embedding,
    embeddedText: text,
  });
}

export const embed = internalAction({
  args: { personId: v.id("people"), attempt: v.optional(v.number()) },
  returns: v.null(),
  handler: async (ctx, args) => {
    const attempt = args.attempt ?? 0;
    try {
      await embedPerson(ctx, args.personId);
    } catch (error) {
      const delayMs = EMBED_RETRY_DELAYS_MS[attempt];
      if (delayMs === undefined) {
        // Out of retries: log and give up rather than throw, so a single
        // stuck person can never surface as an unhandled action failure.
        console.error(
          `embed: giving up on person ${args.personId} after ${attempt + 1} attempts`,
          error,
        );
        return null;
      }
      await ctx.scheduler.runAfter(delayMs, internal.people.embed, {
        personId: args.personId,
        attempt: attempt + 1,
      });
    }
    return null;
  },
});

// ---------------------------------------------------------- semantic search

const searchResultValidator = v.object({
  _id: v.id("people"),
  _creationTime: v.number(),
  name: v.string(),
  link: v.optional(v.string()),
  context: v.optional(v.string()),
  platform: v.optional(v.string()),
  handle: v.optional(v.string()),
  headline: v.optional(v.string()),
  score: v.number(),
});

export const fetchSearchResults = internalQuery({
  args: { ids: v.array(v.id("people")) },
  handler: async (ctx, args) => {
    // Safe without an auth check: internal-only, and the ids come from a
    // vector search already filtered to the caller's userId.
    const people: Array<Doc<"people">> = [];
    for (const id of args.ids) {
      const person = await ctx.db.get("people", id);
      if (person !== null) {
        people.push(person);
      }
    }
    return people.map((person) => ({
      _id: person._id,
      _creationTime: person._creationTime,
      name: person.name,
      link: person.link,
      context: person.context,
      platform: person.platform,
      handle: person.handle,
      headline: person.headline,
    }));
  },
});

// Actions have no ctx.db (guidelines), so an action-side rate-limit check
// has to reach the DB through a mutation. userId here is the caller's own
// identity, derived server-side by the action just above -- not a
// client-supplied authorization key.
export const enforceRateLimit = internalMutation({
  args: {
    userId: v.string(),
    action: v.string(),
    max: v.number(),
    windowMs: v.number(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await checkRateLimit(ctx, args.userId, args.action, args.max, args.windowMs);
    return null;
  },
});

export const semanticSearch = action({
  args: { query: v.string() },
  returns: v.array(searchResultValidator),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await ctx.runMutation(internal.people.enforceRateLimit, {
      userId,
      action: "semanticSearch",
      max: 30,
      windowMs: MINUTE_MS,
    });
    const term = args.query.trim();
    if (term === "") {
      return [];
    }
    const vector = await embedText(term);
    const matches = await ctx.vectorSearch("people", "by_embedding", {
      vector,
      limit: 8,
      filter: (q) => q.eq("userId", userId),
    });
    const strong = matches.filter((m) => m._score >= MIN_SEMANTIC_SCORE);
    if (strong.length === 0) {
      return [];
    }
    const scores = new Map(strong.map((m) => [m._id, m._score]));
    const people: Array<{
      _id: Id<"people">;
      _creationTime: number;
      name: string;
      link?: string;
      context?: string;
      platform?: string;
      handle?: string;
      headline?: string;
    }> = await ctx.runQuery(internal.people.fetchSearchResults, {
      ids: strong.map((m) => m._id),
    });
    return people
      .map((person) => ({ ...person, score: scores.get(person._id) ?? 0 }))
      .sort((a, b) => b.score - a.score);
  },
});

// One-off maintenance: schedule embeddings for people created before the
// semantic search feature. Run with: npx convex run people:backfillEmbeddings
export const listMissingEmbeddings = internalQuery({
  args: {},
  returns: v.array(v.id("people")),
  handler: async (ctx) => {
    const people = await ctx.db.query("people").take(200);
    return people
      .filter((person) => person.embedding === undefined)
      .map((person) => person._id);
  },
});

export const backfillEmbeddings = internalAction({
  args: {},
  returns: v.number(),
  handler: async (ctx) => {
    const ids: Array<Id<"people">> = await ctx.runQuery(
      internal.people.listMissingEmbeddings,
      {},
    );
    let embedded = 0;
    for (const personId of ids) {
      // One bad row must not abort the sweep: this runs unattended from the
      // daily cron, and an aborted loop would re-fail identically every day
      // while everyone behind the bad row stays unembedded.
      try {
        await embedPerson(ctx, personId);
        embedded++;
      } catch (error) {
        console.error(`backfillEmbeddings: skipping ${personId}`, error);
      }
    }
    return embedded;
  },
});

// One-off maintenance: rows written before normalizedName existed (or
// inserted directly by the capture pipeline, which bypasses addPerson)
// are unreachable by search_normalized_name until patched. Run with:
// npx convex run people:backfillNormalizedNames
export const backfillNormalizedNames = internalMutation({
  args: {},
  returns: v.number(),
  handler: async (ctx) => {
    const candidates = await ctx.db.query("people").take(BACKFILL_BATCH_SIZE);
    const missing = candidates.filter(
      (person) => person.normalizedName === undefined,
    );
    for (const person of missing) {
      await ctx.db.patch("people", person._id, {
        normalizedName: normalizeName(person.name),
      });
    }
    return missing.length;
  },
});
