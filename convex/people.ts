import { mutation, QueryCtx, MutationCtx } from "./_generated/server";
import { v } from "convex/values";
import { getAuthUserId } from "@convex-dev/auth/server";

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
