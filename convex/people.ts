import {
  action,
  internalAction,
  internalMutation,
  internalQuery,
  mutation,
  query,
  ActionCtx,
  QueryCtx,
  MutationCtx,
} from "./_generated/server";
import { v } from "convex/values";
import { getAuthUserId } from "@convex-dev/auth/server";
import { internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import { buildEmbedText } from "../src/lib";
import { embedText } from "./openaiClient";

// Bound every list read so the query stays scalable as the table grows.
const RESULT_LIMIT = 20;

// Semantic matches below this cosine similarity read as noise, not memory.
// Tuned against real data during verification.
const MIN_SEMANTIC_SCORE = 0.3;

// Guidelines forbid `any` for ctx; use the proper context union.
async function requireUser(ctx: QueryCtx | MutationCtx) {
  const userId = await getAuthUserId(ctx);
  if (userId === null) {
    throw new Error("Not signed in");
  }
  return userId;
}

export const addPerson = mutation({
  args: { name: v.string() },
  returns: v.id("people"),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const name = args.name.trim();
    if (name === "") {
      throw new Error("Name is required");
    }
    const personId = await ctx.db.insert("people", {
      userId,
      name,
      updatedAt: Date.now(),
    });
    await ctx.scheduler.runAfter(0, internal.people.embed, { personId });
    return personId;
  },
});

export const searchPeople = query({
  args: { query: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const term = args.query.trim();
    if (term === "") {
      return await ctx.db
        .query("people")
        .withIndex("by_user", (q) => q.eq("userId", userId))
        .order("desc")
        .take(RESULT_LIMIT);
    }
    return await ctx.db
      .query("people")
      .withSearchIndex("search_name", (q) =>
        q.search("name", term).eq("userId", userId),
      )
      .take(RESULT_LIMIT);
  },
});

export const getPerson = query({
  args: { id: v.id("people") },
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const person = await ctx.db.get("people", args.id);
    if (person === null || person.userId !== userId) {
      return null;
    }
    return person;
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
    const person = await ctx.db.get("people", args.id);
    if (person === null || person.userId !== userId) {
      throw new Error("Person not found");
    }
    // The detail screen always sends both fields; an omitted (undefined) value
    // means the user cleared that input, so patch unsets the field on purpose.
    // Callers that want to leave a field untouched must resend its current value.
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
  });
  // Idempotent: the stored text is the key for the stored vector.
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
  args: { personId: v.id("people") },
  returns: v.null(),
  handler: async (ctx, args) => {
    await embedPerson(ctx, args.personId);
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

export const semanticSearch = action({
  args: { query: v.string() },
  returns: v.array(searchResultValidator),
  handler: async (ctx, args) => {
    const userId = await getAuthUserId(ctx);
    if (userId === null) {
      throw new Error("Not signed in");
    }
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
    for (const personId of ids) {
      await embedPerson(ctx, personId);
    }
    return ids.length;
  },
});
