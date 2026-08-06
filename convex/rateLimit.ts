// Plain helper, not a registered Convex function -- importing it from
// people.ts and captures.ts needs no _generated/api.d.ts patch.

import { MutationCtx } from "./_generated/server";

// Fixed-window per-user rate limiter backed by the rateLimits table. Not a
// sliding window: a caller right at a window boundary can burst up to
// 2x max, which is an acceptable trade for the denial-of-wallet threat
// model this exists to stop, in return for no extra bookkeeping.
//
// One row per (userId, action). A function with more than one window (e.g.
// a per-minute AND a per-day cap) calls this once per window with distinct
// action names, e.g. "createCapture:minute" and "createCapture:day".
//
// Every existing call site here is left as-is (a working, tested cap, not
// worth touching mid-brief) -- but @convex-dev/rate-limiter (composio.ts's
// xLookupLimiter) is the pattern for any NEW quota from here on: it does
// not admit the races a window scan does under concurrency, or lose quota
// when a mutation fails partway through.
export async function checkRateLimit(
  ctx: MutationCtx,
  userId: string,
  action: string,
  max: number,
  windowMs: number,
): Promise<void> {
  const now = Date.now();
  const existing = await ctx.db
    .query("rateLimits")
    .withIndex("by_user_action", (q) =>
      q.eq("userId", userId).eq("action", action),
    )
    .unique();

  if (existing === null) {
    await ctx.db.insert("rateLimits", {
      userId,
      action,
      windowStart: now,
      count: 1,
    });
    return;
  }

  if (now - existing.windowStart >= windowMs) {
    // Past the window: start a fresh one rather than accumulate forever.
    await ctx.db.patch("rateLimits", existing._id, {
      windowStart: now,
      count: 1,
    });
    return;
  }

  if (existing.count >= max) {
    throw new Error("Too many requests -- please wait a moment");
  }

  await ctx.db.patch("rateLimits", existing._id, {
    count: existing.count + 1,
  });
}
