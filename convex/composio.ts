// Composio owns handle collection for LinkedIn, Instagram and X. Their
// managed OAuth apps return what these platforms hide from Clerk's own
// connections -- proven live: LINKEDIN_GET_MY_INFO answers with vanityName
// ("tony-buildd"), profileUrl and a profilePicture.displayImage, and
// INSTAGRAM_GET_USER_INFO answers with username ("t_n1706") and a
// profile_picture_url for a creator/business account. Clerk keeps signing
// people in; this file never touches identity, only the one verified handle
// -- and, where the same call proves one, the one photo -- a connected
// account gives up. It never downloads the photo itself: iOS gets the URL
// back and imports it, the same handoff the old Clerk flow used.
//
// REST via fetch, mirroring emailClient.ts / openaiClient.ts rather than
// adding a Composio SDK dependency for three endpoints. Shapes below are
// pinned against the live OpenAPI document at
// https://backend.composio.dev/api/v3/openapi.json (checked 2026-08-04), not
// against prose docs -- the hosted docs site did not reliably resolve to the
// exact request/response fields, and the spec is the one thing that cannot
// drift from what the API actually accepts.

import {
  action,
  ActionCtx,
  internalAction,
  internalMutation,
  internalQuery,
} from "./_generated/server";
import { v } from "convex/values";
import { api, internal } from "./_generated/api";
import { requireUser } from "./authz";

const BASE_URL = "https://backend.composio.dev/api/v3";
const MINUTE_MS = 60_000;

function requireEnv(name: string): string {
  const value = process.env[name];
  if (value === undefined || value === "") {
    throw new Error(
      `${name} is not set on the Convex deployment. Run: npx convex env set ${name} <value>`,
    );
  }
  return value;
}

// Haven's platform names are used everywhere else in the app ("x" on the
// card, in profileFields.ts). Composio's toolkit slug for that platform is
// still "twitter" -- the only place the two vocabularies have to meet.
const PLATFORMS = ["linkedin", "instagram", "x"] as const;
export type SocialPlatform = (typeof PLATFORMS)[number];

const TOOLKIT_SLUG: Record<SocialPlatform, string> = {
  linkedin: "linkedin",
  instagram: "instagram",
  x: "twitter",
};

// The one tool per toolkit that answers "who is this account", proven live
// against each platform (see the file header for LinkedIn and Instagram).
// X's exact response shape is inferred from the standard Twitter API v2
// users/me payload, which Composio's tool wraps -- worth confirming against
// a live connection before this ships, the way LinkedIn and Instagram
// already were.
const PROFILE_TOOL: Record<SocialPlatform, string> = {
  linkedin: "LINKEDIN_GET_MY_INFO",
  instagram: "INSTAGRAM_GET_USER_INFO",
  x: "TWITTER_USER_LOOKUP_ME",
};

// Extra arguments a platform's profile tool needs to hand back its photo.
// LinkedIn and Instagram include theirs by default; X's underlying API v2
// only returns profile_image_url when user.fields asks for it. Composio
// tools pass arguments through to the wrapped API mostly verbatim, so
// "user_fields" here is inferred from that convention, the same caveat
// PROFILE_TOOL.x already carries -- not live-proven, and this call is made
// the same way whether the field comes back or not.
const TOOL_ARGUMENTS: Partial<Record<SocialPlatform, Record<string, unknown>>> = {
  x: { user_fields: "profile_image_url" },
};

export const platformValidator = v.union(
  v.literal("linkedin"),
  v.literal("instagram"),
  v.literal("x"),
);

// ---------------------------------------------------------------- transport

async function composioRequest(
  path: string,
  init: RequestInit = {},
): Promise<Response> {
  const apiKey = requireEnv("COMPOSIO_API_KEY");
  return fetch(`${BASE_URL}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      ...(init.headers ?? {}),
    },
  });
}

// A failure body this gets truncated before it ever reaches a thrown Error:
// Convex logs and error-tracking both keep the message whole, and an upstream
// error page or a misbehaving proxy can hand back megabytes of HTML for what
// is, to every caller here, the same "this call failed" outcome.
const MAX_ERROR_DETAIL_LENGTH = 500;

async function composioJson<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const response = await composioRequest(path, init);
  if (!response.ok) {
    const detail = await response.text();
    const truncated =
      detail.length > MAX_ERROR_DETAIL_LENGTH
        ? `${detail.slice(0, MAX_ERROR_DETAIL_LENGTH)}...`
        : detail;
    throw new Error(`Composio ${path} failed (${response.status}): ${truncated}`);
  }
  return (await response.json()) as T;
}

// ------------------------------------------------------------- auth configs

type AuthConfigListResponse = {
  items: Array<{ id: string; toolkit: { slug: string } }>;
};

type AuthConfigCreateResponse = {
  auth_config: { id: string };
};

export const getCachedAuthConfigId = internalQuery({
  args: { toolkit: v.string() },
  returns: v.union(v.string(), v.null()),
  handler: async (ctx, args) => {
    const rows = await ctx.db
      .query("composioAuthConfigs")
      .withIndex("by_toolkit", (q) => q.eq("toolkit", args.toolkit))
      .take(1);
    return rows[0]?.authConfigId ?? null;
  },
});

// Check-then-insert inside one mutation, same as every other idempotent
// creation in this codebase: Convex runs mutations transactionally, so two
// concurrent ensureAuthConfig calls for a toolkit neither has cached yet
// cannot both win the insert, even though both may reach here.
export const cacheAuthConfigId = internalMutation({
  args: { toolkit: v.string(), authConfigId: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const rows = await ctx.db
      .query("composioAuthConfigs")
      .withIndex("by_toolkit", (q) => q.eq("toolkit", args.toolkit))
      .take(1);
    if (rows.length > 0) {
      return null;
    }
    await ctx.db.insert("composioAuthConfigs", args);
    return null;
  },
});

// The auth config is Composio's OAuth app registration for a toolkit --
// created once, ever, and reused by every connection to that toolkit. Three
// places are checked in order, cheapest first: our own cache, then
// Composio's own list (in case one already exists from the dashboard, or a
// deploy that raced this one), and only then a create. A local cache miss
// racing another request's create is a narrow, low-stakes window -- worst
// case Composio ends up with two auth configs for one toolkit, not a broken
// connection -- so this does not try to lock across the network call.
async function ensureAuthConfig(
  ctx: ActionCtx,
  platform: SocialPlatform,
): Promise<string> {
  const toolkit = TOOLKIT_SLUG[platform];
  const cached: string | null = await ctx.runQuery(
    internal.composio.getCachedAuthConfigId,
    { toolkit },
  );
  if (cached !== null) {
    return cached;
  }

  const listed = await composioJson<AuthConfigListResponse>(
    `/auth_configs?toolkit_slug=${encodeURIComponent(toolkit)}`,
  );
  const existing = listed.items.find((item) => item.toolkit.slug === toolkit);
  const authConfigId =
    existing?.id ??
    (
      await composioJson<AuthConfigCreateResponse>("/auth_configs", {
        method: "POST",
        body: JSON.stringify({
          toolkit: { slug: toolkit },
          auth_config: {
            type: "use_composio_managed_auth",
            name: `Haven ${toolkit}`,
          },
        }),
      })
    ).auth_config.id;

  await ctx.runMutation(internal.composio.cacheAuthConfigId, {
    toolkit,
    authConfigId,
  });
  return authConfigId;
}

// --------------------------------------------------------- connected accounts

type ConnectedAccountStatus =
  | "INITIALIZING"
  | "INITIATED"
  | "ACTIVE"
  | "FAILED"
  | "EXPIRED"
  | "INACTIVE"
  | "REVOKED";

type ConnectedAccount = {
  id: string;
  status: ConnectedAccountStatus;
  toolkit: { slug: string };
};

type ConnectedAccountListResponse = { items: ConnectedAccount[] };

type LinkResponse = {
  redirect_url: string;
  connected_account_id: string;
};

type ToolExecuteResponse = {
  data: Record<string, unknown>;
  error: string | null;
  successful: boolean;
};

// A personal Instagram account, not creator/business, is Composio's
// documented limit on this toolkit: the profile tool fails with Meta's own
// OAuthException (code 190 / an HTTP 403 shape), not a Composio-specific
// error. Matched on the message text, which is what a tool-execute failure
// actually gives us -- `error` is a plain string, not a structured code.
function isUnsupportedInstagramAccount(errorMessage: string): boolean {
  const message = errorMessage.toLowerCase();
  return (
    message.includes("oauthexception") ||
    message.includes("(#190)") ||
    message.includes("business and creator") ||
    message.includes("business or creator")
  );
}

// The one field on each platform's profile tool that is the handle, per the
// live-proven shapes in the file header. X's nesting is defensive: Composio
// tools sometimes flatten the upstream response and sometimes pass it
// through, so both `username` and a nested `data.username` are checked.
function extractHandle(
  platform: SocialPlatform,
  data: Record<string, unknown>,
): string | null {
  const read = (key: string): string | null => {
    const value = data[key];
    return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
  };
  if (platform === "linkedin") {
    return read("vanityName");
  }
  if (platform === "instagram") {
    return read("username");
  }
  const direct = read("username");
  if (direct !== null) {
    return direct;
  }
  const nested = data["data"];
  if (nested !== null && typeof nested === "object") {
    const nestedUsername = (nested as Record<string, unknown>)["username"];
    if (typeof nestedUsername === "string" && nestedUsername.trim() !== "") {
      return nestedUsername.trim();
    }
  }
  return null;
}

// The one field on each platform's profile tool that is a photo, per the
// same live-proven shapes: LinkedIn nests it under profilePicture, Instagram
// has it flat. Optional everywhere -- a profile with no photo, or a platform
// that did not hand one back this call, must not fail the connection over
// it, so this returns null rather than throwing either way.
function extractPhotoUrl(
  platform: SocialPlatform,
  data: Record<string, unknown>,
): string | null {
  const read = (key: string): string | null => {
    const value = data[key];
    return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
  };
  if (platform === "linkedin") {
    const picture = data["profilePicture"];
    if (picture === null || typeof picture !== "object") {
      return null;
    }
    const displayImage = (picture as Record<string, unknown>)["displayImage"];
    return typeof displayImage === "string" && displayImage.trim() !== ""
      ? displayImage.trim()
      : null;
  }
  if (platform === "instagram") {
    return read("profile_picture_url");
  }
  // See TOOL_ARGUMENTS.x: only present when user.fields asked for it, and
  // never proven live, so this is the one platform where absent is expected
  // rather than merely tolerated.
  return read("profile_image_url");
}

// Runs the platform's profile tool over an ACTIVE connection and, on
// success, stores the handle it proves. Shared by completeSocialConnection's
// ACTIVE branch and initiateSocialConnection's dedupe branch, so "what a
// connection resolves to" is answered the same way regardless of which path
// found it ACTIVE.
async function resolveAndStoreHandle(
  ctx: ActionCtx,
  platform: SocialPlatform,
  connectedAccountId: string,
  userId: string,
): Promise<
  | { status: "connected"; handle: string; photoUrl?: string }
  | { status: "unsupported_account" }
  | { status: "failed" }
> {
  const toolArguments = TOOL_ARGUMENTS[platform];
  const result = await composioJson<ToolExecuteResponse>(
    `/tools/execute/${PROFILE_TOOL[platform]}`,
    {
      method: "POST",
      body: JSON.stringify({
        connected_account_id: connectedAccountId,
        user_id: userId,
        ...(toolArguments ? { arguments: toolArguments } : {}),
      }),
    },
  );

  if (!result.successful) {
    if (platform === "instagram" && isUnsupportedInstagramAccount(result.error ?? "")) {
      return { status: "unsupported_account" };
    }
    return { status: "failed" };
  }

  const handle = extractHandle(platform, result.data);
  if (handle === null) {
    return { status: "failed" };
  }

  await storeVerifiedHandle(ctx, platform, handle);
  const photoUrl = extractPhotoUrl(platform, result.data);
  return { status: "connected", handle, photoUrl: photoUrl ?? undefined };
}

// Merges the newly proven handle into the card's existing handles rather
// than replacing the array: updateMyProfile's `handles` argument is the
// whole list, and a person who already connected one platform must not lose
// it when a second one lands. Idempotent by construction -- the filter
// always drops this platform's old entry first, so storing the same handle
// twice produces the same array both times, not a duplicate.
async function storeVerifiedHandle(
  ctx: ActionCtx,
  platform: SocialPlatform,
  handle: string,
): Promise<void> {
  const card = await ctx.runQuery(api.profiles.getMyCard, {});
  const existingHandles = card?.handles ?? [];
  const nextHandles = [
    ...existingHandles.filter((existing) => existing.platform !== platform),
    { platform, value: handle, verified: true },
  ];
  await ctx.runMutation(api.profiles.updateMyProfile, {
    handles: nextHandles,
    // The first platform anyone connects becomes what the card leads with;
    // reconnecting an already-primary platform, or adding a second one,
    // leaves that choice alone.
    primaryPlatform: card?.primaryPlatform ?? platform,
  });
}

// ------------------------------------------------------------ public actions

export const initiateSocialConnection = action({
  args: { platform: platformValidator },
  returns: v.union(
    v.object({
      status: v.literal("redirect"),
      redirectUrl: v.string(),
      connectedAccountId: v.string(),
    }),
    v.object({ status: v.literal("already"), handle: v.string() }),
    v.object({ status: v.literal("unsupported_account") }),
    v.object({ status: v.literal("failed") }),
  ),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    // Every branch below makes at least one metered Composio call (a list,
    // sometimes also a tool execution or a link creation), the same
    // denial-of-wallet threat model rateLimit.ts exists for. This is a
    // rarely repeated, user-initiated tap, not a poll, so the cap is tight.
    await ctx.runMutation(internal.people.enforceRateLimit, {
      userId,
      action: "initiateSocialConnection",
      max: 10,
      windowMs: MINUTE_MS,
    });
    const toolkit = TOOLKIT_SLUG[args.platform];

    // One account per toolkit per user: Composio's own list is the source of
    // truth for this, not a local mirror that could drift from it.
    const existing = await composioJson<ConnectedAccountListResponse>(
      `/connected_accounts?user_ids[]=${encodeURIComponent(userId)}&toolkit_slugs[]=${toolkit}&statuses[]=ACTIVE`,
    );
    // Found by toolkit, not taken on faith as items[0]: the query params are
    // a request, not a guarantee, and a filter Composio silently ignored
    // would otherwise resolve and store a handle from the wrong toolkit.
    const match = existing.items.find((item) => item.toolkit.slug === toolkit);
    if (match !== undefined) {
      const outcome = await resolveAndStoreHandle(
        ctx,
        args.platform,
        match.id,
        userId,
      );
      if (outcome.status === "connected") {
        return { status: "already" as const, handle: outcome.handle };
      }
      return outcome;
    }

    const authConfigId = await ensureAuthConfig(ctx, args.platform);
    const link = await composioJson<LinkResponse>("/connected_accounts/link", {
      method: "POST",
      body: JSON.stringify({ auth_config_id: authConfigId, user_id: userId }),
    });
    return {
      status: "redirect" as const,
      redirectUrl: link.redirect_url,
      connectedAccountId: link.connected_account_id,
    };
  },
});

export const completeSocialConnection = action({
  args: { platform: platformValidator, connectedAccountId: v.string() },
  returns: v.union(
    v.object({ status: v.literal("pending") }),
    v.object({
      status: v.literal("connected"),
      handle: v.string(),
      photoUrl: v.optional(v.string()),
    }),
    v.object({ status: v.literal("unsupported_account") }),
    v.object({ status: v.literal("failed") }),
  ),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    // The iOS client polls this every 2s for up to 120s while a browser
    // sheet is open -- roughly 30 calls a minute of genuine use, each one a
    // metered Composio list call and sometimes also a tool execution. 40
    // comfortably covers one real polling loop with room for a client that
    // starts a little early or a request that lands right at a window
    // boundary, while still bounding the same denial-of-wallet threat every
    // other metered action in this codebase is capped against.
    await ctx.runMutation(internal.people.enforceRateLimit, {
      userId,
      action: "completeSocialConnection",
      max: 40,
      windowMs: MINUTE_MS,
    });

    // A connected account id is not a secret the caller minted -- it came
    // back from initiateSocialConnection to whoever asked, and ids are not
    // guaranteed unguessable. Without an authoritative ownership check,
    // polling somebody else's id would write their proven handle onto the
    // caller's own card as "verified".
    //
    // This has to be independent of connected_accounts.user_id: Composio's
    // own OpenAPI spec documents that field as being removed entirely ("we
    // will not be providing userId from this api anymore") and some
    // responses already omit it, so a check that only compared it when
    // present treated its absence as "nothing to check against, so allow" --
    // which is not a narrower guard, it is no guard at all the moment the
    // field is missing. Listing the caller's own connected accounts is the
    // same call initiateSocialConnection already trusts to answer "does this
    // user already have one"; requiring the id to appear in that list is
    // authoritative because the list itself is server-scoped to `userId`,
    // not because of anything the target account's own record claims about
    // itself.
    const owned = await composioJson<ConnectedAccountListResponse>(
      `/connected_accounts?user_ids[]=${encodeURIComponent(userId)}`,
    );
    const account = owned.items.find((item) => item.id === args.connectedAccountId);
    if (account === undefined) {
      return { status: "failed" as const };
    }
    if (account.toolkit.slug !== TOOLKIT_SLUG[args.platform]) {
      return { status: "failed" as const };
    }

    if (account.status === "INITIALIZING" || account.status === "INITIATED") {
      return { status: "pending" as const };
    }
    if (account.status !== "ACTIVE") {
      // FAILED, EXPIRED, INACTIVE, REVOKED: none of these will ever become
      // ACTIVE on their own, so all four are the same "give up" answer to
      // the client polling this.
      return { status: "failed" as const };
    }

    return await resolveAndStoreHandle(
      ctx,
      args.platform,
      args.connectedAccountId,
      userId,
    );
  },
});

// --------------------------------------------------------- account deletion

type ConnectedAccountDeleteResponse = {
  success: boolean;
  revoke_job_id?: string;
};

// Scheduled from profiles.deleteMyAccount rather than called inline: that is
// a mutation, and mutations cannot reach the network. Composio has no idea a
// Convex account was just deleted, and a connected account left alone keeps
// its OAuth tokens alive at Composio under a userId nothing on Haven's side
// will ever look up again.
//
// `revoke_on_delete=true` is load bearing, not a default worth accepting:
// without it, DELETE only soft-deletes the record (Composio's own
// description -- "marking it as deleted... prevents the account from being
// used for API calls but preserves the record") and leaves the upstream
// OAuth credentials live. Revocation runs as Composio's own background job,
// so this does not wait on it -- there is no programmatic way to poll it yet
// per the OpenAPI spec, and nothing here needs to.
//
// Every failure is caught and logged, never rethrown: deleteMyAccount has
// already committed by the time this runs (see its own comment on why),
// and a Composio outage -- no network, a missing COMPOSIO_API_KEY, a 500 --
// must never read as the account deletion having failed. What is left
// behind at worst is a connected account nothing here will ever reference
// again, not a person whose deletion silently did not happen.
export const deleteConnectedAccountsForUser = internalAction({
  args: { userId: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    // Distinct from every failure below: a deployment that has never
    // configured Composio (a preview environment, a fresh clone) is not
    // failing to reach it, it never intended to reach it at all, and logging
    // that as a cleanup failure on every single account deletion would be
    // permanent, uninformative noise in exactly the deployments where nobody
    // can act on it.
    if (process.env.COMPOSIO_API_KEY === undefined || process.env.COMPOSIO_API_KEY === "") {
      return null;
    }

    let accounts: ConnectedAccountListResponse;
    try {
      // No `statuses` filter: an EXPIRED or INACTIVE connection still holds
      // whatever token it last had, and the point of this pass is to reach
      // every one of them, not only the ones still ACTIVE.
      accounts = await composioJson<ConnectedAccountListResponse>(
        `/connected_accounts?user_ids[]=${encodeURIComponent(args.userId)}`,
      );
    } catch (error) {
      console.error(
        `Composio cleanup: could not list connected accounts for ${args.userId}`,
        error,
      );
      return null;
    }

    for (const account of accounts.items) {
      try {
        await composioJson<ConnectedAccountDeleteResponse>(
          `/connected_accounts/${account.id}?revoke_on_delete=true`,
          { method: "DELETE" },
        );
      } catch (error) {
        console.error(
          `Composio cleanup: could not delete connected account ${account.id} for ${args.userId}`,
          error,
        );
      }
    }
    return null;
  },
});
