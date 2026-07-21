import { mutation } from "./_generated/server";
import { v } from "convex/values";
import { ConvexError } from "convex/values";
import { isValidEmail, normalizeEmail } from "../src/lib";
import { checkRateLimit } from "./rateLimit";

// This endpoint is public and unauthenticated, so there is no per-user key to
// throttle on -- the guard is a single global fixed-window cap. It blunts a
// scripted flood of the open write endpoint; the trade is that a genuine burst
// past the cap is briefly turned away, acceptable for a private-beta waitlist.
// The sentinel userId keeps these counters out of any real user's namespace.
export const MAX_JOINS_PER_MINUTE = 40;
const RATE_WINDOW_MS = 60_000;
const RATE_SENTINEL = "public:waitlist";

// Public, unauthenticated join for the /#/join waitlist. Rate-limits first so
// every attempt (valid or not) counts against the flood cap, then validates
// and normalizes server-side (never trust the client's check), then dedupes on
// the normalized email so a second submit is idempotent rather than a
// duplicate row. Returns a small status the landing maps to its success state
// either way -- "already" is a success, not an error, so we never leak whether
// an address was seen before.
export const joinWaitlist = mutation({
  args: {
    name: v.string(),
    email: v.string(),
    source: v.union(v.literal("desktop"), v.literal("phone")),
  },
  returns: v.object({
    status: v.union(v.literal("joined"), v.literal("already")),
  }),
  handler: async (ctx, args) => {
    await checkRateLimit(
      ctx,
      RATE_SENTINEL,
      "joinWaitlist",
      MAX_JOINS_PER_MINUTE,
      RATE_WINDOW_MS,
    );

    const name = args.name.trim();
    if (name === "") {
      throw new ConvexError("Enter your name.");
    }

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

    await ctx.db.insert("waitlist", { name, email, source: args.source });
    return { status: "joined" as const };
  },
});
