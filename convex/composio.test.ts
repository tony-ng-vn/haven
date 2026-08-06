/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import rateLimiterTest from "@convex-dev/rate-limiter/test";

const modules = import.meta.glob("./**/*.ts");

function newHarness() {
  const t = convexTest(schema, modules);
  // The X-lookup caps (composio.ts's xLookupLimiter) run through the
  // rate-limiter component now, not the hand-rolled rateLimits table --
  // convex-test needs the component registered before anything that calls
  // it can run.
  rateLimiterTest.register(t);
  return t;
}
type Harness = ReturnType<typeof newHarness>;

let nextSubject = 0;
function asNewUser(t: Harness) {
  const subject = `composio_user_${nextSubject++}`;
  const issuer = "https://test.clerk.accounts.dev";
  const userId = `${issuer}|${subject}`;
  return { userId, as: t.withIdentity({ subject, issuer }) };
}

type SeededHandle = { platform: "instagram" | "x" | "linkedin" | "phone"; value: string; verified: boolean };

async function seedProfile(
  t: Harness,
  userId: string,
  fields: {
    username: string;
    handles?: SeededHandle[];
    primaryPlatform?: SeededHandle["platform"];
  },
) {
  await t.run(async (ctx) => {
    await ctx.db.insert("profiles", {
      userId,
      username: fields.username,
      name: "Tony Nguyen",
      handles: fields.handles,
      primaryPlatform: fields.primaryPlatform,
      updatedAt: Date.now(),
    });
  });
}

type FetchCall = { url: string; method: string; body?: Record<string, unknown> };

// Routes each call by path and method the way the real backend would, and
// lets each test hand in only the responses its scenario needs -- everything
// else falls back to a bland success so a test only has to describe what it
// actually cares about.
function stubComposio(overrides: {
  listAuthConfigs?: () => unknown;
  createAuthConfig?: () => unknown;
  link?: () => unknown;
  listConnectedAccounts?: () => unknown;
  getConnectedAccount?: () => unknown;
  executeTool?: (toolSlug: string) => unknown;
  deleteConnectedAccount?: (id: string) => unknown;
}) {
  const calls: FetchCall[] = [];
  vi.stubGlobal(
    "fetch",
    async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      const method = init?.method ?? "GET";
      const body = init?.body
        ? (JSON.parse(String(init.body)) as Record<string, unknown>)
        : undefined;
      calls.push({ url, method, body });

      if (url.includes("/auth_configs?")) {
        return Response.json(overrides.listAuthConfigs?.() ?? { items: [] });
      }
      if (url.endsWith("/auth_configs") && method === "POST") {
        return Response.json(
          overrides.createAuthConfig?.() ?? {
            toolkit: { slug: "linkedin" },
            auth_config: {
              id: "ac_test",
              auth_scheme: "OAUTH2",
              is_composio_managed: true,
            },
          },
        );
      }
      if (url.endsWith("/connected_accounts/link") && method === "POST") {
        return Response.json(
          overrides.link?.() ?? {
            link_token: "tok",
            redirect_url: "https://backend.composio.dev/redirect",
            expires_at: "2026-08-04T00:00:00Z",
            connected_account_id: "ca_test",
          },
        );
      }
      if (url.includes("/connected_accounts?")) {
        if (overrides.listConnectedAccounts) {
          return Response.json(overrides.listConnectedAccounts());
        }
        // Falls back to wrapping getConnectedAccount's shape as the caller's
        // one owned account: completeSocialConnection now discovers an
        // account by listing rather than by a direct GET, and most scenarios
        // here are only describing "the one account this test is about", not
        // testing the list/single-GET distinction itself. A test about
        // ownership specifically (the account is NOT the caller's) sets
        // listConnectedAccounts directly instead, since this fallback cannot
        // tell which user's list is being asked for.
        if (overrides.getConnectedAccount) {
          return Response.json({ items: [overrides.getConnectedAccount()] });
        }
        return Response.json({ items: [] });
      }
      if (/\/connected_accounts\/[^/?]+$/.test(url) && method === "GET") {
        return Response.json(
          overrides.getConnectedAccount?.() ?? {
            id: "ca_test",
            status: "ACTIVE",
            toolkit: { slug: "linkedin" },
          },
        );
      }
      const deleteMatch = url.match(
        /\/connected_accounts\/([^/?]+)\?revoke_on_delete=true$/,
      );
      if (deleteMatch && method === "DELETE") {
        return Response.json(
          overrides.deleteConnectedAccount?.(deleteMatch[1]) ?? {
            success: true,
          },
        );
      }
      const toolMatch = url.match(/\/tools\/execute\/([^/?]+)$/);
      if (toolMatch) {
        return Response.json(
          overrides.executeTool?.(toolMatch[1]) ?? {
            data: {},
            error: null,
            successful: true,
          },
        );
      }
      throw new Error(`Unhandled Composio fetch in a test: ${method} ${url}`);
    },
  );
  return calls;
}

beforeEach(() => {
  vi.stubEnv("COMPOSIO_API_KEY", "test-composio-key");
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

test("initiate creates an auth config once and links a fresh connection", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  // No profile row: the redirect branch proves nothing and stores nothing
  // yet, so it must not touch profiles.ts at all.
  const calls = stubComposio({});

  const result = await as.action(api.composio.initiateSocialConnection, {
    platform: "linkedin",
  });

  expect(result).toEqual({
    status: "redirect",
    redirectUrl: "https://backend.composio.dev/redirect",
    connectedAccountId: "ca_test",
  });
  const created = calls.find(
    (call) => call.url.endsWith("/auth_configs") && call.method === "POST",
  );
  expect(created?.body).toMatchObject({ toolkit: { slug: "linkedin" } });
  const linked = calls.find((call) => call.url.endsWith("/connected_accounts/link"));
  expect(linked?.body).toMatchObject({ auth_config_id: "ac_test" });
});

test("a second toolkit connection reuses the cached auth config", async () => {
  const t = newHarness();
  const first = await asNewUser(t);
  const second = await asNewUser(t);
  const calls = stubComposio({});

  await first.as.action(api.composio.initiateSocialConnection, {
    platform: "linkedin",
  });
  const createsAfterFirst = calls.filter(
    (call) => call.url.endsWith("/auth_configs") && call.method === "POST",
  ).length;
  await second.as.action(api.composio.initiateSocialConnection, {
    platform: "linkedin",
  });
  const createsAfterSecond = calls.filter(
    (call) => call.url.endsWith("/auth_configs") && call.method === "POST",
  ).length;

  expect(createsAfterFirst).toBe(1);
  // The cache table absorbed the second call: no second auth config, and no
  // second list either, once the row exists.
  expect(createsAfterSecond).toBe(1);
});

test("an auth config already registered in Composio's own list is reused, not duplicated", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const calls = stubComposio({
    listAuthConfigs: () => ({
      items: [{ id: "ac_from_dashboard", toolkit: { slug: "linkedin" } }],
    }),
  });

  const result = await as.action(api.composio.initiateSocialConnection, {
    platform: "linkedin",
  });

  expect(result).toMatchObject({ status: "redirect" });
  expect(
    calls.some((call) => call.url.endsWith("/auth_configs") && call.method === "POST"),
  ).toBe(false);
  const linked = calls.find((call) => call.url.endsWith("/connected_accounts/link"));
  expect(linked?.body).toMatchObject({ auth_config_id: "ac_from_dashboard" });
});

test("completing a connected account that belongs to a different toolkit is rejected, not trusted", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  // Platform says linkedin, but the account this id actually points at is an
  // instagram connection -- a copy-paste bug or a guessed id, either way this
  // must not run LinkedIn's profile tool against it.
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "instagram" },
    }),
  });

  const result = await as.action(api.composio.completeSocialConnection, {
    platform: "linkedin",
    connectedAccountId: "ca_test",
  });

  expect(result).toEqual({ status: "failed" });
  const card = await as.query(api.profiles.getMyCard, {});
  expect(card?.handles ?? []).toEqual([]);
});

test("completing a connected account owned by a different user is rejected", async () => {
  const t = newHarness();
  const guesser = await asNewUser(t);
  await seedProfile(t, guesser.userId, { username: "guesser" });
  // The guesser's own list does not contain this id -- it belongs to
  // somebody else, whatever Composio's single-account GET might once have
  // said about it (see the "no user_id field at all" test above for why
  // that field is not trusted at all anymore).
  stubComposio({
    listConnectedAccounts: () => ({ items: [] }),
  });

  const result = await guesser.as.action(api.composio.completeSocialConnection, {
    platform: "linkedin",
    connectedAccountId: "ca_test",
  });

  expect(result).toEqual({ status: "failed" });
  const card = await guesser.as.query(api.profiles.getMyCard, {});
  expect(card?.handles ?? []).toEqual([]);
});

// BLOCKER: Composio's own OpenAPI spec documents user_id as being removed
// from this response ("we will not be providing userId from this api
// anymore"). A check that only compares user_id when it happens to be
// present treats its absence as "nothing to check against, so allow" --
// which means a guesser who passes somebody else's connectedAccountId
// succeeds the moment Composio omits the field, no guessing about *whose*
// id required. Ownership has to be authoritative and independent of this
// field: proven by asking Composio which connected accounts belong to the
// caller, not by reading a field on the target account that the caller
// could not have forged but Composio might simply not send.
test("a connected account with no user_id field at all is still rejected when it is not the caller's", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "guesser" });
  stubComposio({
    // The caller's own list is empty: this account does not belong to them,
    // whatever the single-account GET below might have said about it.
    listConnectedAccounts: () => ({ items: [] }),
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "linkedin" },
      // No user_id at all.
    }),
    executeTool: () => ({
      data: { vanityName: "not-the-caller" },
      error: null,
      successful: true,
    }),
  });

  const result = await as.action(api.composio.completeSocialConnection, {
    platform: "linkedin",
    connectedAccountId: "ca_test",
  });

  expect(result).toEqual({ status: "failed" });
  const card = await as.query(api.profiles.getMyCard, {});
  expect(card?.handles ?? []).toEqual([]);
});

test("initiate short-circuits on an existing ACTIVE connection instead of creating a duplicate", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  const calls = stubComposio({
    listConnectedAccounts: () => ({
      items: [{ id: "ca_existing", status: "ACTIVE", toolkit: { slug: "linkedin" } }],
    }),
    executeTool: (tool) => {
      expect(tool).toBe("LINKEDIN_GET_MY_INFO");
      return { data: { vanityName: "tony-buildd" }, error: null, successful: true };
    },
  });

  const result = await as.action(api.composio.initiateSocialConnection, {
    platform: "linkedin",
  });

  expect(result).toEqual({ status: "already", handle: "tony-buildd" });
  // No auth config work and no new link: the dedupe path never reaches them.
  expect(calls.some((call) => call.url.endsWith("/connected_accounts/link"))).toBe(
    false,
  );
  const card = await as.query(api.profiles.getMyCard, {});
  expect(card?.handles).toEqual([
    { platform: "linkedin", value: "tony-buildd", verified: true },
  ]);
});

test("completing while INITIATED reports pending, not connected", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "INITIATED",
      toolkit: { slug: "linkedin" },
    }),
  });

  const result = await as.action(api.composio.completeSocialConnection, {
    platform: "linkedin",
    connectedAccountId: "ca_test",
  });

  expect(result).toEqual({ status: "pending" });
});

test("completing an ACTIVE connection stores the proven handle as verified", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  // Already has an X handle from onboarding -- connecting LinkedIn afterward
  // must add to that, not replace it.
  await seedProfile(t, userId, {
    username: "tony",
    handles: [{ platform: "x", value: "tonybuildd", verified: true }],
    primaryPlatform: "x",
  });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "linkedin" },
    }),
    executeTool: () => ({
      data: {
        vanityName: "tony-buildd",
        profileUrl: "https://linkedin.com/in/tony-buildd",
        profilePicture: { displayImage: "https://media.licdn.com/dms/image/tony.jpg" },
      },
      error: null,
      successful: true,
    }),
  });

  const result = await as.action(api.composio.completeSocialConnection, {
    platform: "linkedin",
    connectedAccountId: "ca_test",
  });

  // LinkedIn's photo is nested under profilePicture.displayImage -- this is
  // the one place that read is proven, everywhere else photoUrl is tested on
  // its own.
  expect(result).toEqual({
    status: "connected",
    handle: "tony-buildd",
    photoUrl: "https://media.licdn.com/dms/image/tony.jpg",
  });
  const card = await as.query(api.profiles.getMyCard, {});
  expect(card?.handles).toEqual(
    expect.arrayContaining([
      { platform: "x", value: "tonybuildd", verified: true },
      { platform: "linkedin", value: "tony-buildd", verified: true },
    ]),
  );
  // The platform connected first keeps leading the card.
  expect(card?.primaryPlatform).toBe("x");
});

// A platform's own stable id, alongside the handle, so identity's dedup
// (people.ts's findHandleOwner) can still find the account after a rename.
// LinkedIn's shape is proven live: a flat "id" beside vanityName.
test("LinkedIn's platform id is read from its flat id field", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "linkedin" },
    }),
    executeTool: () => ({
      data: { vanityName: "tony-buildd", id: "urn:li:person:abc123" },
      error: null,
      successful: true,
    }),
  });

  await as.action(api.composio.completeSocialConnection, {
    platform: "linkedin",
    connectedAccountId: "ca_test",
  });

  const card = await as.query(api.profiles.getMyCard, {});
  expect(card?.handles).toEqual([
    {
      platform: "linkedin",
      value: "tony-buildd",
      verified: true,
      platformId: "urn:li:person:abc123",
    },
  ]);
});

// Instagram's Graph API names its stable id "user_id" on some callers and
// "id" on others -- both are tried, user_id first.
test("Instagram's platform id prefers user_id over id when both are present", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "instagram" },
    }),
    executeTool: () => ({
      data: { username: "t_n1706", user_id: "ig_user_1", id: "ig_id_1" },
      error: null,
      successful: true,
    }),
  });

  await as.action(api.composio.completeSocialConnection, {
    platform: "instagram",
    connectedAccountId: "ca_test",
  });

  const card = await as.query(api.profiles.getMyCard, {});
  expect(card?.handles).toEqual([
    { platform: "instagram", value: "t_n1706", verified: true, platformId: "ig_user_1" },
  ]);
});

test("Instagram's platform id falls back to id when user_id is absent", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "instagram" },
    }),
    executeTool: () => ({
      data: { username: "t_n1706", id: "ig_id_only" },
      error: null,
      successful: true,
    }),
  });

  await as.action(api.composio.completeSocialConnection, {
    platform: "instagram",
    connectedAccountId: "ca_test",
  });

  const card = await as.query(api.profiles.getMyCard, {});
  expect(card?.handles).toEqual([
    { platform: "instagram", value: "t_n1706", verified: true, platformId: "ig_id_only" },
  ]);
});

// X's id is nested the same defensive way its username is (extractHandle's
// own comment): both a flat "id" and a nested "data.id" are checked.
test("X's platform id is read the same defensive way its username is", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "twitter" }, // Composio's slug for X
    }),
    executeTool: () => ({
      data: { username: "tonybuildd", id: "x_id_1" },
      error: null,
      successful: true,
    }),
  });

  await as.action(api.composio.completeSocialConnection, {
    platform: "x",
    connectedAccountId: "ca_test",
  });

  const card = await as.query(api.profiles.getMyCard, {});
  expect(card?.handles).toEqual([
    { platform: "x", value: "tonybuildd", verified: true, platformId: "x_id_1" },
  ]);
});

// A profile tool shape with no id anywhere must not fail the connection
// over it -- the handle is still proven and stored, just without a
// platformId, the same "absent is tolerated" doctrine extractPhotoUrl uses.
test("a profile tool with no id anywhere stores the handle without a platformId", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "twitter" }, // Composio's slug for X
    }),
    executeTool: () => ({
      data: { username: "tonybuildd" },
      error: null,
      successful: true,
    }),
  });

  await as.action(api.composio.completeSocialConnection, {
    platform: "x",
    connectedAccountId: "ca_test",
  });

  const card = await as.query(api.profiles.getMyCard, {});
  expect(card?.handles).toEqual([
    { platform: "x", value: "tonybuildd", verified: true },
  ]);
});

test("Instagram's photo comes from its own flat profile_picture_url field", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "instagram" },
    }),
    executeTool: () => ({
      data: {
        username: "t_n1706",
        profile_picture_url: "https://scontent.cdninstagram.com/tony.jpg",
      },
      error: null,
      successful: true,
    }),
  });

  const result = await as.action(api.composio.completeSocialConnection, {
    platform: "instagram",
    connectedAccountId: "ca_test",
  });

  expect(result).toEqual({
    status: "connected",
    handle: "t_n1706",
    photoUrl: "https://scontent.cdninstagram.com/tony.jpg",
  });
});

test("X's photo is read when the tool call returns it", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "twitter" }, // Composio's slug for X
    }),
    executeTool: () => ({
      data: { username: "tonybuildd", profile_image_url: "https://pbs.twimg.com/tony.jpg" },
      error: null,
      successful: true,
    }),
  });

  const result = await as.action(api.composio.completeSocialConnection, {
    platform: "x",
    connectedAccountId: "ca_test",
  });

  expect(result).toEqual({
    status: "connected",
    handle: "tonybuildd",
    photoUrl: "https://pbs.twimg.com/tony.jpg",
  });
});

test("X's photo is simply absent, not an error, when the field never comes back", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "twitter" }, // Composio's slug for X
    }),
    executeTool: () => ({
      data: { username: "tonybuildd" },
      error: null,
      successful: true,
    }),
  });

  const result = await as.action(api.composio.completeSocialConnection, {
    platform: "x",
    connectedAccountId: "ca_test",
  });

  expect(result).toEqual({ status: "connected", handle: "tonybuildd" });
  expect("photoUrl" in result).toBe(false);
});

test("X's tool call asks for profile_image_url via user_fields", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  const calls = stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "twitter" }, // Composio's slug for X
    }),
    executeTool: () => ({
      data: { username: "tonybuildd" },
      error: null,
      successful: true,
    }),
  });

  await as.action(api.composio.completeSocialConnection, {
    platform: "x",
    connectedAccountId: "ca_test",
  });

  const executed = calls.find((call) => call.url.includes("/tools/execute/TWITTER_USER_LOOKUP_ME"));
  expect(executed?.body).toMatchObject({ arguments: { user_fields: "profile_image_url" } });
});

test("Instagram's unsupported-account path is unaffected by the photo read", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "instagram" },
    }),
    executeTool: () => ({
      data: {},
      error: "Instagram API error: (#190) This endpoint requires a business or creator account",
      successful: false,
    }),
  });

  const result = await as.action(api.composio.completeSocialConnection, {
    platform: "instagram",
    connectedAccountId: "ca_test",
  });

  expect(result).toEqual({ status: "unsupported_account" });
});

test("storing the same verified handle twice does not duplicate it", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "linkedin" },
    }),
    executeTool: () => ({
      data: { vanityName: "tony-buildd" },
      error: null,
      successful: true,
    }),
  });

  await as.action(api.composio.completeSocialConnection, {
    platform: "linkedin",
    connectedAccountId: "ca_test",
  });
  // The iOS client polls this on a timer, so a second call landing after the
  // first already stored the handle is the normal case, not an edge case.
  await as.action(api.composio.completeSocialConnection, {
    platform: "linkedin",
    connectedAccountId: "ca_test",
  });

  const card = await as.query(api.profiles.getMyCard, {});
  expect(card?.handles).toEqual([
    { platform: "linkedin", value: "tony-buildd", verified: true },
  ]);
});

test("an Instagram personal account maps to unsupported_account, not a generic failure", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "instagram" },
    }),
    executeTool: () => ({
      data: {},
      error: "Instagram API error: (#190) This endpoint requires a business or creator account",
      successful: false,
    }),
  });

  const result = await as.action(api.composio.completeSocialConnection, {
    platform: "instagram",
    connectedAccountId: "ca_test",
  });

  expect(result).toEqual({ status: "unsupported_account" });
  // Nothing gets stored on a rejected account.
  const card = await as.query(api.profiles.getMyCard, {});
  expect(card?.handles ?? []).toEqual([]);
});

test("an Instagram failure that merely contains the digits 190 is a generic failure, not a wrong-account-type", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "ACTIVE",
      toolkit: { slug: "instagram" },
    }),
    executeTool: () => ({
      data: {},
      error: "Rate limited: retry after 190 seconds",
      successful: false,
    }),
  });

  const result = await as.action(api.composio.completeSocialConnection, {
    platform: "instagram",
    connectedAccountId: "ca_test",
  });

  expect(result).toEqual({ status: "failed" });
});

test("a FAILED connection reports failed, not pending", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "FAILED",
      toolkit: { slug: "twitter" }, // Composio's slug for X
    }),
  });

  const result = await as.action(api.composio.completeSocialConnection, {
    platform: "x",
    connectedAccountId: "ca_test",
  });

  expect(result).toEqual({ status: "failed" });
});

test("an EXPIRED connection also reports failed", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  stubComposio({
    getConnectedAccount: () => ({
      id: "ca_test",
      status: "EXPIRED",
      toolkit: { slug: "twitter" }, // Composio's slug for X
    }),
  });

  const result = await as.action(api.composio.completeSocialConnection, {
    platform: "x",
    connectedAccountId: "ca_test",
  });

  expect(result).toEqual({ status: "failed" });
});

test("a missing COMPOSIO_API_KEY throws a clear, actionable error", async () => {
  vi.unstubAllEnvs();
  const t = newHarness();
  const { as } = await asNewUser(t);

  await expect(
    as.action(api.composio.initiateSocialConnection, { platform: "linkedin" }),
  ).rejects.toThrow(/COMPOSIO_API_KEY/);
});

// ------------------------------------------------------ resolveXPlatformId

test("resolveXPlatformId resolves the caller's connected account and writes the id onto the person's x handle", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  const person = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Tony Nguyen",
    contactHandles: [{ platform: "x", value: "tonybuildd" }],
    context: "met at the demo day",
  });
  if (person.status !== "created") throw new Error("unreachable");

  const calls = stubComposio({
    listConnectedAccounts: () => ({
      items: [{ id: "ca_test", status: "ACTIVE", toolkit: { slug: "twitter" } }],
    }),
    executeTool: () => ({ data: { id: "x_id_1" }, error: null, successful: true }),
  });

  const result = await as.action(api.composio.resolveXPlatformId, {
    personId: person.personId,
    username: "tonybuildd",
  });

  expect(result).toEqual({ status: "resolved", platformId: "x_id_1" });
  const saved = await as.query(api.people.getPerson, { id: person.personId });
  expect(saved?.contactHandles).toEqual([
    expect.objectContaining({
      platform: "x",
      value: "tonybuildd",
      platformId: "x_id_1",
    }),
  ]);
  const executed = calls.find((call) =>
    call.url.includes("/tools/execute/TWITTER_USER_LOOKUP_BY_USERNAME"),
  );
  expect(executed?.body).toMatchObject({
    connected_account_id: "ca_test",
    user_id: userId,
    arguments: { username: "tonybuildd" },
  });
});

test("resolveXPlatformId reports unavailable when the caller has no connected X account", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const person = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Tony Nguyen",
    contactHandles: [{ platform: "x", value: "tonybuildd" }],
    context: "met at the demo day",
  });
  if (person.status !== "created") throw new Error("unreachable");

  // The ordinary case for most users -- graceful, not an error.
  stubComposio({ listConnectedAccounts: () => ({ items: [] }) });

  const result = await as.action(api.composio.resolveXPlatformId, {
    personId: person.personId,
    username: "tonybuildd",
  });

  expect(result).toEqual({ status: "unavailable" });
  const saved = await as.query(api.people.getPerson, { id: person.personId });
  expect(saved?.contactHandles?.[0]).not.toHaveProperty("platformId");
});

test("resolveXPlatformId reports failed, never throws, when Composio's lookup fails", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const person = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Tony Nguyen",
    contactHandles: [{ platform: "x", value: "tonybuildd" }],
    context: "met at the demo day",
  });
  if (person.status !== "created") throw new Error("unreachable");

  stubComposio({
    listConnectedAccounts: () => ({
      items: [{ id: "ca_test", status: "ACTIVE", toolkit: { slug: "twitter" } }],
    }),
    executeTool: () => ({
      data: {},
      error: "rate limited",
      successful: false,
    }),
  });

  const result = await as.action(api.composio.resolveXPlatformId, {
    personId: person.personId,
    username: "tonybuildd",
  });

  expect(result).toEqual({ status: "failed" });
});

test("resolveXPlatformId refuses a person that does not belong to the caller, before spending any Composio call", async () => {
  const t = newHarness();
  const owner = await asNewUser(t);
  const guesser = await asNewUser(t);
  const person = await owner.as.mutation(api.people.addPersonWithOutcome, {
    name: "Tony Nguyen",
    contactHandles: [{ platform: "x", value: "tonybuildd" }],
    context: "met at the demo day",
  });
  if (person.status !== "created") throw new Error("unreachable");

  const calls = stubComposio({});

  const result = await guesser.as.action(api.composio.resolveXPlatformId, {
    personId: person.personId,
    username: "tonybuildd",
  });

  expect(result).toEqual({ status: "failed" });
  // Ownership is checked before any metered call is made, or a guessed
  // person id would still cost the real owner's rate-limit budget.
  expect(calls).toHaveLength(0);
});

test("resolveXPlatformId resolves the id but refuses to patch a handle the username no longer matches", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  // The card has since been renamed away from what the caller's stale
  // username argument still says.
  const person = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Tony Nguyen",
    contactHandles: [{ platform: "x", value: "newhandle" }],
    context: "met at the demo day",
  });
  if (person.status !== "created") throw new Error("unreachable");

  stubComposio({
    listConnectedAccounts: () => ({
      items: [{ id: "ca_test", status: "ACTIVE", toolkit: { slug: "twitter" } }],
    }),
    executeTool: () => ({ data: { id: "x_id_1" }, error: null, successful: true }),
  });

  const result = await as.action(api.composio.resolveXPlatformId, {
    personId: person.personId,
    username: "oldhandle",
  });

  // The lookup itself still succeeds -- Composio genuinely resolved this
  // username to an id -- but the write is refused because it would staple a
  // stale username's id onto the handle that has since been renamed.
  expect(result).toEqual({ status: "resolved", platformId: "x_id_1" });
  const saved = await as.query(api.people.getPerson, { id: person.personId });
  expect(saved?.contactHandles?.[0]).not.toHaveProperty("platformId");
});

// S9: a malformed 200 (Composio itself misbehaving, not erroring) must not
// throw past the outcome contract -- resolveXPlatformId promises exactly
// three statuses, never an unhandled exception.
test("resolveXPlatformId reports failed rather than throwing on a malformed connected-accounts response", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const person = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Tony Nguyen",
    contactHandles: [{ platform: "x", value: "tonybuildd" }],
    context: "met at the demo day",
  });
  if (person.status !== "created") throw new Error("unreachable");

  // No "items" key at all -- a shape composioJson happily parses as JSON,
  // so it never throws inside the fetch stub or composioJson itself; only
  // code that assumes `.items` exists ever finds out.
  stubComposio({ listConnectedAccounts: () => ({}) });

  const result = await as.action(api.composio.resolveXPlatformId, {
    personId: person.personId,
    username: "tonybuildd",
  });

  expect(result).toEqual({ status: "failed" });
});

test("resolveXPlatformId reports failed rather than throwing on a null tool result", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const person = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Tony Nguyen",
    contactHandles: [{ platform: "x", value: "tonybuildd" }],
    context: "met at the demo day",
  });
  if (person.status !== "created") throw new Error("unreachable");

  stubComposio({
    listConnectedAccounts: () => ({
      items: [{ id: "ca_test", status: "ACTIVE", toolkit: { slug: "twitter" } }],
    }),
    // successful: true but data is null -- a shape extractPlatformId has to
    // survive without a caller-visible throw.
    executeTool: () => ({ data: null, error: null, successful: true }),
  });

  const result = await as.action(api.composio.resolveXPlatformId, {
    personId: person.personId,
    username: "tonybuildd",
  });

  expect(result).toEqual({ status: "failed" });
});

// ------------------------------------------------------ resolveXUsername

test("resolveXUsername resolves an id with no personId to authz -- identical flow, minus the person", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);

  const calls = stubComposio({
    listConnectedAccounts: () => ({
      items: [{ id: "ca_test", status: "ACTIVE", toolkit: { slug: "twitter" } }],
    }),
    executeTool: () => ({ data: { id: "x_id_1" }, error: null, successful: true }),
  });

  const result = await as.action(api.composio.resolveXUsername, {
    username: "tonybuildd",
  });

  expect(result).toEqual({ status: "resolved", platformId: "x_id_1" });
  const executed = calls.find((call) =>
    call.url.includes("/tools/execute/TWITTER_USER_LOOKUP_BY_USERNAME"),
  );
  expect(executed?.body).toMatchObject({
    connected_account_id: "ca_test",
    user_id: userId,
    arguments: { username: "tonybuildd" },
  });
});

test("resolveXUsername reports unavailable when the caller has no connected X account", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  stubComposio({ listConnectedAccounts: () => ({ items: [] }) });

  const result = await as.action(api.composio.resolveXUsername, {
    username: "tonybuildd",
  });

  expect(result).toEqual({ status: "unavailable" });
});

test("resolveXUsername reports failed, never throws, when Composio's lookup fails", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  stubComposio({
    listConnectedAccounts: () => ({
      items: [{ id: "ca_test", status: "ACTIVE", toolkit: { slug: "twitter" } }],
    }),
    executeTool: () => ({ data: {}, error: "rate limited", successful: false }),
  });

  const result = await as.action(api.composio.resolveXUsername, {
    username: "tonybuildd",
  });

  expect(result).toEqual({ status: "failed" });
});

test("resolveXUsername reports failed rather than throwing on a malformed connected-accounts response", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  stubComposio({ listConnectedAccounts: () => ({ items: null }) });

  const result = await as.action(api.composio.resolveXUsername, {
    username: "tonybuildd",
  });

  expect(result).toEqual({ status: "failed" });
});

// The review's own wallet-risk number (14.4k calls/day): a shared daily cap
// across BOTH X-lookup actions, on top of each one's own per-minute cap, so
// alternating between them cannot double the effective daily budget.
test("resolveXPlatformId and resolveXUsername share one daily cap", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const person = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Tony Nguyen",
    contactHandles: [{ platform: "x", value: "tonybuildd" }],
    context: "met at the demo day",
  });
  if (person.status !== "created") throw new Error("unreachable");
  stubComposio({
    listConnectedAccounts: () => ({
      items: [{ id: "ca_test", status: "ACTIVE", toolkit: { slug: "twitter" } }],
    }),
    executeTool: () => ({ data: { id: "x_id_1" }, error: null, successful: true }),
  });

  const DAILY_CAP = 50;
  vi.useFakeTimers();
  // W4: xLookupDay is epoch-aligned (composio.ts's start: 0), so its
  // boundary falls at every UTC midnight. Left at whatever real instant the
  // test happened to start, a run within ~25 minutes of midnight would
  // cross that boundary mid-loop, hand the bucket a fresh day's capacity,
  // and let the 51st call through instead of refusing it -- pinned well
  // clear of any midnight so the ~25 minutes advanced below can never
  // cross one.
  vi.setSystemTime(new Date("2026-01-01T00:05:00.000Z"));
  try {
    // Split across both actions rather than calling one 50 times: a
    // per-action cap would let this pass with room to spare, and only a
    // truly shared bucket refuses on the 51st call regardless of which
    // action it was. Advanced past a minute between pairs so each action's
    // OWN 10/minute cap never trips first and masks what this test is
    // actually proving -- the calls still land the same calendar day, so
    // the daily bucket itself never resets.
    for (let i = 0; i < DAILY_CAP / 2; i++) {
      await as.action(api.composio.resolveXPlatformId, {
        personId: person.personId,
        username: "tonybuildd",
      });
      await as.action(api.composio.resolveXUsername, { username: "tonybuildd" });
      vi.advanceTimersByTime(61_000);
    }

    await expect(
      as.action(api.composio.resolveXUsername, { username: "tonybuildd" }),
    ).rejects.toThrow(/Too many requests/);
  } finally {
    vi.useRealTimers();
  }
});

// -------------------------------------------------- deleteMyAccount cleanup

test("deleting an account deletes every one of that user's connected accounts, revoking tokens", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  const calls = stubComposio({
    listConnectedAccounts: () => ({
      items: [
        { id: "ca_linkedin", status: "ACTIVE", toolkit: { slug: "linkedin" } },
        { id: "ca_x", status: "EXPIRED", toolkit: { slug: "twitter" } },
      ],
    }),
  });

  vi.useFakeTimers();
  try {
    await as.mutation(api.profiles.deleteMyAccount, {});
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  } finally {
    vi.useRealTimers();
  }

  const listCall = calls.find((call) => call.url.includes("/connected_accounts?"));
  expect(listCall?.url).toContain("user_ids[]=");
  expect(listCall?.url).toContain(encodeURIComponent(userId));

  const deletedIds = calls
    .filter((call) => call.method === "DELETE")
    .map((call) => call.url);
  expect(deletedIds).toHaveLength(2);
  // revoke_on_delete=true is load bearing -- without it Composio only
  // soft-deletes the record and leaves the upstream OAuth token alive.
  expect(deletedIds.every((url) => url.includes("revoke_on_delete=true"))).toBe(true);
  expect(deletedIds.some((url) => url.includes("ca_linkedin"))).toBe(true);
  expect(deletedIds.some((url) => url.includes("ca_x"))).toBe(true);
});

test("deleteMyAccount succeeds even when every Composio call fails", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  await seedProfile(t, userId, { username: "tony" });
  vi.stubGlobal("fetch", async () => {
    throw new Error("simulated network failure");
  });

  vi.useFakeTimers();
  try {
    // The mutation itself never touches the network, so this must resolve
    // regardless of what the scheduled Composio cleanup later runs into.
    await expect(as.mutation(api.profiles.deleteMyAccount, {})).resolves.toBeNull();
    // Flushing the scheduled cleanup must not surface its failure either --
    // deleteConnectedAccountsForUser catches it internally.
    await expect(
      t.finishAllScheduledFunctions(vi.runAllTimers),
    ).resolves.not.toThrow();
  } finally {
    vi.useRealTimers();
  }

  const profile = await t.run((ctx) =>
    ctx.db
      .query("profiles")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .unique(),
  );
  expect(profile).toBeNull();
});

test("the cleanup action itself tolerates a Composio failure on the delete call", async () => {
  const t = newHarness();
  const { userId } = await asNewUser(t);
  stubComposio({
    listConnectedAccounts: () => ({
      items: [{ id: "ca_linkedin", status: "ACTIVE", toolkit: { slug: "linkedin" } }],
    }),
    deleteConnectedAccount: () => {
      throw new Error("simulated Composio 500");
    },
  });

  await expect(
    t.action(internal.composio.deleteConnectedAccountsForUser, { userId }),
  ).resolves.toBeNull();
});

test("the cleanup action tolerates a missing COMPOSIO_API_KEY the same way", async () => {
  vi.unstubAllEnvs();
  const t = newHarness();
  const { userId } = await asNewUser(t);

  await expect(
    t.action(internal.composio.deleteConnectedAccountsForUser, { userId }),
  ).resolves.toBeNull();
});
