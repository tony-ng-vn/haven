// Plain validators and policy helpers, not registered Convex functions --
// schema.ts and stripe.ts both need this exact shape, and one definition is
// what keeps the stored document and the mutation arguments from drifting
// apart (same reasoning as profileFields.ts).

import { v } from "convex/values";

// Mirrors Stripe's own subscription status strings verbatim rather than
// collapsing them to a boolean at the write site. Storing the raw status
// keeps the access policy in one place (grantsProAccess below), so changing
// our mind about, say, past_due is a one-line edit and not a migration.
export const subscriptionStatusValidator = v.union(
  v.literal("incomplete"),
  v.literal("incomplete_expired"),
  v.literal("trialing"),
  v.literal("active"),
  v.literal("past_due"),
  v.literal("canceled"),
  v.literal("unpaid"),
  v.literal("paused"),
);

export type SubscriptionStatus = typeof subscriptionStatusValidator.type;

// The statuses that unlock Pro. past_due is deliberately included: Stripe is
// still running Smart Retries at that point, and revoking access on the first
// temporary card decline churns customers who would have paid on the retry.
// Once retries are exhausted Stripe moves the subscription to canceled or
// unpaid, both of which cut access here.
const ACCESS_GRANTING: ReadonlySet<string> = new Set([
  "trialing",
  "active",
  "past_due",
]);

export function grantsProAccess(status: SubscriptionStatus): boolean {
  return ACCESS_GRANTING.has(status);
}
