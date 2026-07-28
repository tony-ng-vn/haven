/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import Stripe from "stripe";
import { beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import { grantsProAccess } from "./stripeFields";

const modules = import.meta.glob("./**/*.ts");

const WEBHOOK_SECRET = "whsec_test_secret_for_signing_only";
const USER = "https://clerk.example.dev|user_abc";

// The SDK's own signer, so these tests exercise the real signature format
// rather than a hand-rolled approximation of it.
const stripe = new Stripe("sk_test_unused", {
  httpClient: Stripe.createFetchHttpClient(),
});

beforeEach(() => {
  vi.stubEnv("STRIPE_WEBHOOK_SECRET", WEBHOOK_SECRET);
});

/** A Stripe subscription event body shaped like the real thing. */
function subscriptionEvent(
  type: string,
  overrides: {
    id?: string;
    created?: number;
    status?: string;
    subscriptionId?: string;
    clerkUserId?: string | null;
    currentPeriodEnd?: number;
    cancelAtPeriodEnd?: boolean;
  } = {},
) {
  const metadata =
    overrides.clerkUserId === null
      ? {}
      : { clerkUserId: overrides.clerkUserId ?? USER };
  return JSON.stringify({
    id: overrides.id ?? "evt_1",
    object: "event",
    type,
    created: overrides.created ?? 1_700_000_000,
    data: {
      object: {
        id: overrides.subscriptionId ?? "sub_123",
        object: "subscription",
        customer: "cus_123",
        status: overrides.status ?? "active",
        cancel_at_period_end: overrides.cancelAtPeriodEnd ?? false,
        metadata,
        // current_period_end lives on the ITEM, not the subscription, as of
        // API version 2026-06-24 -- this fixture encodes that on purpose.
        items: {
          object: "list",
          data: [
            {
              id: "si_123",
              object: "subscription_item",
              current_period_end: overrides.currentPeriodEnd ?? 1_787_892_693,
            },
          ],
        },
      },
    },
  });
}

async function postWebhook(
  t: ReturnType<typeof convexTest>,
  body: string,
  signature?: string,
) {
  const header =
    signature ??
    (await stripe.webhooks.generateTestHeaderStringAsync({
      payload: body,
      secret: WEBHOOK_SECRET,
    }));
  return await t.fetch("/stripe/webhook", {
    method: "POST",
    headers: { "stripe-signature": header },
    body,
  });
}

const asUser = (t: ReturnType<typeof convexTest>) =>
  t.withIdentity({ tokenIdentifier: USER });

describe("grantsProAccess", () => {
  test("past_due keeps access so a retryable decline does not churn the user", () => {
    expect(grantsProAccess("active")).toBe(true);
    expect(grantsProAccess("trialing")).toBe(true);
    expect(grantsProAccess("past_due")).toBe(true);
  });

  test("terminal and not-yet-paid statuses do not grant access", () => {
    expect(grantsProAccess("canceled")).toBe(false);
    expect(grantsProAccess("unpaid")).toBe(false);
    expect(grantsProAccess("incomplete")).toBe(false);
    expect(grantsProAccess("incomplete_expired")).toBe(false);
    expect(grantsProAccess("paused")).toBe(false);
  });
});

describe("webhook signature verification", () => {
  test("a body with no Stripe-Signature header is rejected and stores nothing", async () => {
    const t = convexTest(schema, modules);

    const res = await t.fetch("/stripe/webhook", {
      method: "POST",
      body: subscriptionEvent("customer.subscription.created"),
    });

    expect(res.status).toBe(400);
    const rows = await t.run((ctx) => ctx.db.query("subscriptions").collect());
    expect(rows).toHaveLength(0);
  });

  test("a forged signature is rejected and stores nothing", async () => {
    const t = convexTest(schema, modules);
    const body = subscriptionEvent("customer.subscription.created");

    // Correctly formatted, but signed with a secret we do not trust.
    const forged = await stripe.webhooks.generateTestHeaderStringAsync({
      payload: body,
      secret: "whsec_an_attackers_own_secret",
    });
    const res = await postWebhook(t, body, forged);

    expect(res.status).toBe(400);
    const rows = await t.run((ctx) => ctx.db.query("subscriptions").collect());
    expect(rows).toHaveLength(0);
  });

  test("a signature over a DIFFERENT body is rejected", async () => {
    const t = convexTest(schema, modules);

    // Sign the real payload, then tamper with the body that gets sent.
    const signed = await stripe.webhooks.generateTestHeaderStringAsync({
      payload: subscriptionEvent("customer.subscription.created"),
      secret: WEBHOOK_SECRET,
    });
    const tampered = subscriptionEvent("customer.subscription.created", {
      clerkUserId: "https://clerk.example.dev|attacker",
    });
    const res = await postWebhook(t, tampered, signed);

    expect(res.status).toBe(400);
    const rows = await t.run((ctx) => ctx.db.query("subscriptions").collect());
    expect(rows).toHaveLength(0);
  });
});

describe("subscription lifecycle", () => {
  test("a signed created event stores the row and grants access", async () => {
    const t = convexTest(schema, modules);

    const res = await postWebhook(
      t,
      subscriptionEvent("customer.subscription.created"),
    );
    expect(res.status).toBe(200);

    const rows = await t.run((ctx) => ctx.db.query("subscriptions").collect());
    expect(rows).toHaveLength(1);
    expect(rows[0].userId).toBe(USER);
    expect(rows[0].stripeSubscriptionId).toBe("sub_123");
    expect(rows[0].status).toBe("active");
    // Proves the period end was read off the item, not the absent
    // subscription-level field (which would land here as NaN or undefined).
    expect(rows[0].currentPeriodEnd).toBe(1_787_892_693);

    expect(await asUser(t).query(api.stripe.hasProAccess, {})).toBe(true);
  });

  test("deleting the subscription drops access", async () => {
    const t = convexTest(schema, modules);

    await postWebhook(t, subscriptionEvent("customer.subscription.created"));
    expect(await asUser(t).query(api.stripe.hasProAccess, {})).toBe(true);

    const res = await postWebhook(
      t,
      subscriptionEvent("customer.subscription.deleted", {
        id: "evt_2",
        created: 1_700_000_100,
        status: "canceled",
      }),
    );
    expect(res.status).toBe(200);

    expect(await asUser(t).query(api.stripe.hasProAccess, {})).toBe(false);
  });

  test("a past_due event keeps access while Stripe retries", async () => {
    const t = convexTest(schema, modules);

    await postWebhook(t, subscriptionEvent("customer.subscription.created"));
    await postWebhook(
      t,
      subscriptionEvent("customer.subscription.updated", {
        id: "evt_2",
        created: 1_700_000_100,
        status: "past_due",
      }),
    );

    expect(await asUser(t).query(api.stripe.hasProAccess, {})).toBe(true);
  });

  test("a user with no subscription at all has no access", async () => {
    const t = convexTest(schema, modules);
    expect(await asUser(t).query(api.stripe.hasProAccess, {})).toBe(false);
  });

  test("one user's subscription does not grant another user access", async () => {
    const t = convexTest(schema, modules);

    await postWebhook(t, subscriptionEvent("customer.subscription.created"));

    const stranger = t.withIdentity({
      tokenIdentifier: "https://clerk.example.dev|user_stranger",
    });
    expect(await stranger.query(api.stripe.hasProAccess, {})).toBe(false);
  });
});

describe("delivery hazards", () => {
  test("redelivering the same event is a no-op", async () => {
    const t = convexTest(schema, modules);
    const body = subscriptionEvent("customer.subscription.created");

    await postWebhook(t, body);
    const res = await postWebhook(t, body);

    // Stripe retries on any non-2xx, so a duplicate must still answer 200 --
    // answering 400 would put Stripe into a pointless retry loop.
    expect(res.status).toBe(200);
    const rows = await t.run((ctx) => ctx.db.query("subscriptions").collect());
    expect(rows).toHaveLength(1);
  });

  test("an out-of-order stale event does not resurrect a cancelled subscription", async () => {
    const t = convexTest(schema, modules);

    await postWebhook(
      t,
      subscriptionEvent("customer.subscription.created", {
        id: "evt_1",
        created: 1_700_000_000,
      }),
    );
    await postWebhook(
      t,
      subscriptionEvent("customer.subscription.deleted", {
        id: "evt_2",
        created: 1_700_000_100,
        status: "canceled",
      }),
    );

    // Stripe does not guarantee ordering: an "active" update emitted BEFORE
    // the cancellation can arrive after it. It must not restore access.
    const res = await postWebhook(
      t,
      subscriptionEvent("customer.subscription.updated", {
        id: "evt_3",
        created: 1_700_000_050,
        status: "active",
      }),
    );

    expect(res.status).toBe(200);
    expect(await asUser(t).query(api.stripe.hasProAccess, {})).toBe(false);
  });

  test("an event carrying no clerkUserId is dropped, never mis-assigned", async () => {
    const t = convexTest(schema, modules);

    const res = await postWebhook(
      t,
      subscriptionEvent("customer.subscription.created", {
        clerkUserId: null,
      }),
    );

    // Acknowledged, because no retry can ever add the missing metadata and a
    // non-2xx would earn three days of backoff retries for nothing. What
    // matters is that it grants nobody anything.
    expect(res.status).toBe(200);
    const rows = await t.run((ctx) => ctx.db.query("subscriptions").collect());
    expect(rows).toHaveLength(0);
  });

  test("an event type we do not handle is acknowledged, not retried", async () => {
    const t = convexTest(schema, modules);

    const res = await postWebhook(t, subscriptionEvent("invoice.paid"));

    expect(res.status).toBe(200);
    const rows = await t.run((ctx) => ctx.db.query("subscriptions").collect());
    expect(rows).toHaveLength(0);
  });

  test("a missing webhook secret fails closed instead of trusting the body", async () => {
    const t = convexTest(schema, modules);
    vi.stubEnv("STRIPE_WEBHOOK_SECRET", "");

    const res = await postWebhook(
      t,
      subscriptionEvent("customer.subscription.created"),
    );

    expect(res.status).toBe(500);
    const rows = await t.run((ctx) => ctx.db.query("subscriptions").collect());
    expect(rows).toHaveLength(0);
  });
});
