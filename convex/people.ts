import { mutation, query, QueryCtx, MutationCtx } from "./_generated/server";
import { v } from "convex/values";
import { getAuthUserId } from "@convex-dev/auth/server";

// Bound every list read so the query stays scalable as the table grows.
const RESULT_LIMIT = 20;

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
    return await ctx.db.insert("people", {
      userId,
      name,
      updatedAt: Date.now(),
    });
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
    return null;
  },
});
