// Entitlement, mirrored from Stripe. Every write here is internal and reached
// only from the verified webhook route in http.ts: if a client could call it,
// anyone could grant themselves Pro.

import { v } from "convex/values";
import { internalMutation, query } from "./_generated/server";
import { grantsProAccess, subscriptionStatusValidator } from "./stripeFields";

// A user is never expected to hold more than one or two subscriptions (a
// cancelled one plus its replacement), so this bound only exists to keep the
// read from being unbounded as guidelines require.
const MAX_SUBSCRIPTIONS_PER_USER = 20;

export const applySubscriptionEvent = internalMutation({
  args: {
    userId: v.string(),
    stripeCustomerId: v.string(),
    stripeSubscriptionId: v.string(),
    status: subscriptionStatusValidator,
    currentPeriodEnd: v.number(),
    cancelAtPeriodEnd: v.boolean(),
    // Stripe's event.created, in unix seconds.
    eventCreated: v.number(),
  },
  returns: v.union(v.literal("applied"), v.literal("stale")),
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("subscriptions")
      .withIndex("by_stripeSubscriptionId", (q) =>
        q.eq("stripeSubscriptionId", args.stripeSubscriptionId),
      )
      .unique();

    // Stripe redelivers on any non-2xx and makes no ordering guarantee, so
    // both hazards are handled by the same rule: only strictly newer events
    // count. A redelivery compares equal and is skipped; an "active" update
    // that overtakes the cancellation it preceded is skipped too, which is
    // what stops a cancelled subscription coming back to life.
    if (existing !== null && args.eventCreated <= existing.lastEventCreated) {
      return "stale";
    }

    const fields = {
      userId: args.userId,
      source: "stripe" as const,
      stripeCustomerId: args.stripeCustomerId,
      stripeSubscriptionId: args.stripeSubscriptionId,
      status: args.status,
      currentPeriodEnd: args.currentPeriodEnd,
      cancelAtPeriodEnd: args.cancelAtPeriodEnd,
      lastEventCreated: args.eventCreated,
      updatedAt: Date.now(),
    };

    if (existing === null) {
      await ctx.db.insert("subscriptions", fields);
    } else {
      await ctx.db.patch("subscriptions", existing._id, fields);
    }
    return "applied";
  },
});

// Gates Pro features. Returns false rather than throwing when signed out:
// this is read to decide what the UI offers, and a signed-out visitor simply
// has no Pro access.
export const hasProAccess = query({
  args: {},
  returns: v.boolean(),
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity === null) {
      return false;
    }
    const rows = await ctx.db
      .query("subscriptions")
      .withIndex("by_user", (q) => q.eq("userId", identity.tokenIdentifier))
      .take(MAX_SUBSCRIPTIONS_PER_USER);

    // Any granting row wins: a user who resubscribed holds a dead row and a
    // live one, and the live one is what matters.
    return rows.some((row) => grantsProAccess(row.status));
  },
});
