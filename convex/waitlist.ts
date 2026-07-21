import { mutation } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import { isValidEmail, normalizeEmail } from "../src/lib";

// Public, unauthenticated join for the /#/join waitlist. Validates and
// normalizes server-side (never trust the client's check), then dedupes on
// the normalized email so a second submit is idempotent rather than a
// duplicate row. Returns a small status the landing maps to its success
// state either way -- "already" is a success, not an error, so we never leak
// whether an address was seen before.
export const joinWaitlist = mutation({
  args: {
    email: v.string(),
    source: v.union(v.literal("desktop"), v.literal("phone")),
  },
  returns: v.object({
    status: v.union(v.literal("joined"), v.literal("already")),
  }),
  handler: async (ctx, args) => {
    const email = normalizeEmail(args.email);
    if (!isValidEmail(email)) {
      throw new ConvexError("Enter a valid email address.");
    }

    const existing = await ctx.db
      .query("waitlist")
      .withIndex("by_email", (q) => q.eq("email", email))
      .unique();
    if (existing !== null) {
      return { status: "already" as const };
    }

    await ctx.db.insert("waitlist", { email, source: args.source });
    return { status: "joined" as const };
  },
});
