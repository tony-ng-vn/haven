import {
  internalAction,
  internalMutation,
  internalQuery,
  mutation,
  query,
  QueryCtx,
  MutationCtx,
} from "./_generated/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc } from "./_generated/dataModel";
import { extractProfile } from "./openaiClient";

// Clerk has no local users table, so tokenIdentifier ("issuer|subject") is
// the stable ownership key -- guidelines say prefer it over `subject` alone.
async function requireUser(ctx: QueryCtx | MutationCtx) {
  const identity = await ctx.auth.getUserIdentity();
  if (identity === null) {
    throw new Error("Not signed in");
  }
  return identity.tokenIdentifier;
}

const extractedValidator = v.object({
  platform: v.string(),
  name: v.string(),
  handle: v.optional(v.string()),
  headline: v.optional(v.string()),
  bio: v.optional(v.string()),
});

export const generateUploadUrl = mutation({
  args: {},
  returns: v.string(),
  handler: async (ctx) => {
    await requireUser(ctx);
    return await ctx.storage.generateUploadUrl();
  },
});

export const createCapture = mutation({
  args: { screenshotId: v.id("_storage") },
  returns: v.id("captures"),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const captureId = await ctx.db.insert("captures", {
      userId,
      screenshotId: args.screenshotId,
      status: "pending",
    });
    await ctx.scheduler.runAfter(0, internal.captures.extract, { captureId });
    return captureId;
  },
});

export const getCapture = internalQuery({
  args: { captureId: v.id("captures") },
  handler: async (ctx, args) => {
    return await ctx.db.get("captures", args.captureId);
  },
});

export const finishExtract = internalMutation({
  args: { captureId: v.id("captures"), extracted: extractedValidator },
  returns: v.null(),
  handler: async (ctx, args) => {
    const capture = await ctx.db.get("captures", args.captureId);
    if (capture === null) {
      return null; // discarded while extraction was running
    }
    await ctx.db.patch("captures", args.captureId, {
      status: "ready",
      extracted: args.extracted,
    });
    return null;
  },
});

export const failExtract = internalMutation({
  args: { captureId: v.id("captures"), error: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const capture = await ctx.db.get("captures", args.captureId);
    if (capture === null) {
      return null;
    }
    await ctx.db.patch("captures", args.captureId, {
      status: "failed",
      error: args.error,
    });
    return null;
  },
});

export const extract = internalAction({
  args: { captureId: v.id("captures") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const capture: Doc<"captures"> | null = await ctx.runQuery(
      internal.captures.getCapture,
      { captureId: args.captureId },
    );
    if (capture === null) {
      return null;
    }
    try {
      const imageUrl = await ctx.storage.getUrl(capture.screenshotId);
      if (imageUrl === null) {
        throw new Error("The screenshot file is missing");
      }
      const extracted = await extractProfile(imageUrl);
      await ctx.runMutation(internal.captures.finishExtract, {
        captureId: args.captureId,
        extracted,
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Extraction failed";
      await ctx.runMutation(internal.captures.failExtract, {
        captureId: args.captureId,
        error: message,
      });
    }
    return null;
  },
});

export const listCaptures = query({
  args: {},
  returns: v.array(
    v.object({
      _id: v.id("captures"),
      _creationTime: v.number(),
      status: v.union(
        v.literal("pending"),
        v.literal("ready"),
        v.literal("failed"),
      ),
      extracted: v.optional(extractedValidator),
      error: v.optional(v.string()),
      imageUrl: v.union(v.string(), v.null()),
    }),
  ),
  handler: async (ctx) => {
    const userId = await requireUser(ctx);
    const captures = await ctx.db
      .query("captures")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .take(50);
    return await Promise.all(
      captures.map(async (capture) => ({
        _id: capture._id,
        _creationTime: capture._creationTime,
        status: capture.status,
        extracted: capture.extracted,
        error: capture.error,
        imageUrl: await ctx.storage.getUrl(capture.screenshotId),
      })),
    );
  },
});

export const acceptCapture = mutation({
  args: {
    captureId: v.id("captures"),
    link: v.optional(v.string()),
    context: v.optional(v.string()),
  },
  returns: v.id("people"),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const capture = await ctx.db.get("captures", args.captureId);
    if (capture === null || capture.userId !== userId) {
      throw new Error("Capture not found");
    }
    if (capture.status !== "ready" || capture.extracted === undefined) {
      throw new Error("Capture is not ready");
    }
    const personId = await ctx.db.insert("people", {
      userId,
      name: capture.extracted.name,
      link: args.link,
      context: args.context,
      updatedAt: Date.now(),
      platform: capture.extracted.platform,
      handle: capture.extracted.handle,
      headline: capture.extracted.headline,
      // The screenshot stays with the person as a visual memory anchor.
      screenshotId: capture.screenshotId,
    });
    await ctx.db.delete("captures", args.captureId);
    await ctx.scheduler.runAfter(0, internal.people.embed, { personId });
    return personId;
  },
});

export const discardCapture = mutation({
  args: { captureId: v.id("captures") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const capture = await ctx.db.get("captures", args.captureId);
    if (capture === null || capture.userId !== userId) {
      throw new Error("Capture not found");
    }
    await ctx.storage.delete(capture.screenshotId);
    await ctx.db.delete("captures", args.captureId);
    return null;
  },
});
