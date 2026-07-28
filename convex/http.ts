import { httpRouter } from "convex/server";
import Stripe from "stripe";
import { internal } from "./_generated/api";
import { httpAction } from "./_generated/server";
import type { SubscriptionStatus } from "./stripeFields";

// Verification never calls the Stripe API, so this instance needs no working
// key -- it exists only to reach stripe.webhooks. The fetch HTTP client and
// the SubtleCrypto provider are both required: Convex runs on V8, not Node,
// so the SDK's default Node http and synchronous crypto are unavailable.
const stripe = new Stripe(
  process.env.STRIPE_SECRET_KEY ?? "sk_unused_for_signature_verification",
  { httpClient: Stripe.createFetchHttpClient() },
);
const cryptoProvider = Stripe.createSubtleCryptoProvider();

// Only these three carry authoritative subscription state. A failed payment
// already reaches us as an update (Stripe flips the status to past_due, then
// to canceled or unpaid once retries run out), so subscribing to invoice
// events as well would be duplicate work -- guidelines say listen only to the
// events the integration actually requires.
const HANDLED_EVENTS: ReadonlySet<string> = new Set([
  "customer.subscription.created",
  "customer.subscription.updated",
  "customer.subscription.deleted",
]);

const KNOWN_STATUSES: ReadonlySet<string> = new Set([
  "incomplete",
  "incomplete_expired",
  "trialing",
  "active",
  "past_due",
  "canceled",
  "unpaid",
  "paused",
]);

type ParsedSubscription = {
  stripeSubscriptionId: string;
  stripeCustomerId: string;
  status: SubscriptionStatus;
  currentPeriodEnd: number;
  cancelAtPeriodEnd: boolean;
  clerkUserId: string;
};

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null
    ? (value as Record<string, unknown>)
    : null;
}

// Narrows the verified event body. The signature proves Stripe sent it, not
// that it has the shape this code expects, so every field is still checked.
function parseSubscription(data: unknown): ParsedSubscription | string {
  const sub = asRecord(data);
  if (sub === null) return "event data is not an object";

  const id = sub.id;
  if (typeof id !== "string") return "subscription id missing";

  // `customer` is an id string unless the event was configured to expand it.
  const customer =
    typeof sub.customer === "string"
      ? sub.customer
      : (asRecord(sub.customer)?.id ?? null);
  if (typeof customer !== "string") return "customer id missing";

  const status = sub.status;
  if (typeof status !== "string" || !KNOWN_STATUSES.has(status)) {
    return `unrecognized subscription status: ${String(status)}`;
  }

  // The only link back to a Haven user, so whatever starts a subscription is
  // obliged to stamp it: checkout must send
  // `subscription_data[metadata][clerkUserId]` set to the Clerk
  // tokenIdentifier. Putting it on the CUSTOMER instead is the easy mistake
  // and would strand every event here.
  const clerkUserId = asRecord(sub.metadata)?.clerkUserId;
  if (typeof clerkUserId !== "string" || clerkUserId === "") {
    return "subscription metadata carries no clerkUserId";
  }

  // As of API version 2026-06-24 current_period_end lives on the subscription
  // ITEM, not the subscription. Every item on a subscription shares the same
  // period, so the first one is the period.
  const items = asRecord(sub.items)?.data;
  const firstItem = Array.isArray(items) ? asRecord(items[0]) : null;
  const periodEnd = firstItem?.current_period_end;
  if (typeof periodEnd !== "number") {
    // Deliberately not fatal: status is what gates access, and dropping a
    // cancellation over a missing timestamp would be worse than storing 0.
    // Logged loudly because absence means the payload shape has drifted.
    console.error(
      `Stripe subscription ${id} had no item current_period_end; storing 0`,
    );
  }

  return {
    stripeSubscriptionId: id,
    stripeCustomerId: customer,
    status: status as SubscriptionStatus,
    currentPeriodEnd: typeof periodEnd === "number" ? periodEnd : 0,
    cancelAtPeriodEnd: sub.cancel_at_period_end === true,
    clerkUserId,
  };
}

const http = httpRouter();

http.route({
  path: "/stripe/webhook",
  method: "POST",
  handler: httpAction(async (ctx, req) => {
    const secret = process.env.STRIPE_WEBHOOK_SECRET;
    if (secret === undefined || secret === "") {
      // Fail closed. Without the secret nothing can be verified, and treating
      // an unverifiable body as trustworthy is the entire vulnerability.
      console.error("STRIPE_WEBHOOK_SECRET is not set; refusing webhook");
      return new Response("Webhook not configured", { status: 500 });
    }

    const signature = req.headers.get("stripe-signature");
    if (signature === null) {
      return new Response("Missing signature", { status: 400 });
    }

    // Verify the exact bytes Stripe signed. Parsing and re-serializing first
    // would change the JSON and invalidate the signature.
    const payload = await req.text();

    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(
        payload,
        signature,
        secret,
        undefined,
        cryptoProvider,
      );
    } catch (error) {
      // Covers a forged signature, a tampered body, and a timestamp outside
      // the tolerance window, which is Stripe's replay-attack guard.
      console.error("Rejected Stripe webhook:", error);
      return new Response("Invalid signature", { status: 400 });
    }

    if (!HANDLED_EVENTS.has(event.type)) {
      // 200, not 404: any non-2xx puts Stripe into a retry loop for an event
      // this integration will never act on.
      return new Response(null, { status: 200 });
    }

    const parsed = parseSubscription(event.data.object);
    if (typeof parsed === "string") {
      // A real integration bug -- most likely checkout failed to stamp
      // metadata -- but a permanent one: this event will never parse, however
      // many times Stripe sends it. Answering non-2xx would buy three days of
      // exponential-backoff retries and a failed-webhook email for something
      // no retry can fix, so acknowledge it and leave the diagnosis in the
      // Convex logs.
      console.error(`Malformed Stripe event ${event.id}: ${parsed}`);
      return new Response(null, { status: 200 });
    }

    await ctx.runMutation(internal.stripe.applySubscriptionEvent, {
      userId: parsed.clerkUserId,
      stripeCustomerId: parsed.stripeCustomerId,
      stripeSubscriptionId: parsed.stripeSubscriptionId,
      status: parsed.status,
      currentPeriodEnd: parsed.currentPeriodEnd,
      cancelAtPeriodEnd: parsed.cancelAtPeriodEnd,
      eventCreated: event.created,
    });

    return new Response(null, { status: 200 });
  }),
});

export default http;
