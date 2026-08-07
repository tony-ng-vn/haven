import { ConvexError, v } from "convex/values";
import {
  mutation,
  query,
  env,
  type MutationCtx,
  type QueryCtx,
} from "./_generated/server";
import { components } from "./_generated/api";
import { requireUser } from "./authz";
import { RateLimiter } from "@convex-dev/rate-limiter";

const MINUTE_MS = 60_000;
const MAX_CODE_LENGTH = 128;

const previewLimiter = new RateLimiter(components.rateLimiter, {
  checkPreviewCode: {
    kind: "fixed window",
    rate: 120,
    period: MINUTE_MS,
    start: 0,
  },
  redeemPreviewCode: {
    kind: "fixed window",
    rate: 10,
    period: MINUTE_MS,
    start: 0,
  },
});

async function enforcePreviewLimit(
  ctx: MutationCtx,
  name: "checkPreviewCode" | "redeemPreviewCode",
  key: string,
): Promise<void> {
  const result = await previewLimiter.limit(ctx, name, { key });
  if (!result.ok) {
    throw new Error("Too many requests -- please wait a moment");
  }
}

function matchesConfiguredCode(raw: string): boolean {
  const submitted = raw.trim();
  if (submitted === "" || submitted.length > MAX_CODE_LENGTH) return false;

  const configured = env.HAVEN_PREVIEW_CODE.trim();
  if (configured === "") {
    throw new ConvexError("Preview access is temporarily unavailable.");
  }
  return submitted === configured;
}

async function grantForUser(
  ctx: QueryCtx | MutationCtx,
  userId: string,
) {
  return await ctx.db
    .query("previewAccess")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .unique();
}

// Signed-out visitors check the shared code before Haven opens Clerk. This is
// only the first half of the gate: no authorization is stored until the same
// code is redeemed by an authenticated account below.
export const checkCode = mutation({
  args: { code: v.string() },
  returns: v.object({
    status: v.union(v.literal("valid"), v.literal("invalid")),
  }),
  handler: async (ctx, args) => {
    await enforcePreviewLimit(ctx, "checkPreviewCode", "public:preview");
    return {
      status: matchesConfiguredCode(args.code)
        ? ("valid" as const)
        : ("invalid" as const),
    };
  },
});

// The authenticated half of the gate. Check and insert share one Convex
// mutation, so two tabs redeeming together still create exactly one grant.
export const redeemCode = mutation({
  args: { code: v.string() },
  returns: v.object({
    status: v.union(
      v.literal("granted"),
      v.literal("already"),
      v.literal("invalid"),
    ),
  }),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await enforcePreviewLimit(ctx, "redeemPreviewCode", userId);

    if ((await grantForUser(ctx, userId)) !== null) {
      return { status: "already" as const };
    }
    if (!matchesConfiguredCode(args.code)) {
      return { status: "invalid" as const };
    }

    await ctx.db.insert("previewAccess", {
      userId,
      grantedAt: Date.now(),
    });
    return { status: "granted" as const };
  },
});

export const hasAccess = query({
  args: {},
  returns: v.boolean(),
  handler: async (ctx) => {
    const userId = await requireUser(ctx);
    return (await grantForUser(ctx, userId)) !== null;
  },
});
