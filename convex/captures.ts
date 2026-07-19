import {
  internalAction,
  internalMutation,
  internalQuery,
  mutation,
  query,
} from "./_generated/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc } from "./_generated/dataModel";
import { extractProfile } from "./openaiClient";
import { requireUser } from "./authz";
import { checkRateLimit } from "./rateLimit";

const MINUTE_MS = 60_000;
const DAY_MS = 24 * 60 * 60_000;
const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

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
    // Denial-of-wallet guard: extraction calls a paid model, so cap both
    // the burst rate and the daily spend per user.
    await checkRateLimit(ctx, userId, "createCapture:minute", 10, MINUTE_MS);
    await checkRateLimit(ctx, userId, "createCapture:day", 100, DAY_MS);

    // Never trust the client's claim about what it uploaded -- read the
    // real metadata Convex recorded for the blob before touching anything
    // else, and delete the blob outright when it fails validation.
    const meta = await ctx.db.system.get("_storage", args.screenshotId);
    const isValidImage =
      meta !== null &&
      meta.contentType !== undefined &&
      meta.contentType.startsWith("image/") &&
      meta.size <= MAX_UPLOAD_BYTES;
    if (!isValidImage) {
      if (meta !== null) {
        await ctx.storage.delete(args.screenshotId);
      }
      throw new Error("Please upload an image under 10 MB");
    }

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

// Messages already written to be shown to a user as-is: specific, no
// upstream/API leakage. Anything else is raw error text (OpenAI response
// bodies, env-var hints) that must never reach the client -- it goes into
// errorDetail instead, behind a short generic message.
const SAFE_ERROR_MESSAGES = new Set([
  "Could not read a profile in this screenshot",
  "The screenshot file is missing",
]);
const GENERIC_ERROR_MESSAGE = "Could not read this screenshot -- you can retry";

export const failExtract = internalMutation({
  args: { captureId: v.id("captures"), error: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const capture = await ctx.db.get("captures", args.captureId);
    if (capture === null) {
      return null;
    }
    const isSafe = SAFE_ERROR_MESSAGES.has(args.error);
    await ctx.db.patch("captures", args.captureId, {
      status: "failed",
      error: isSafe ? args.error : GENERIC_ERROR_MESSAGE,
      errorDetail: isSafe ? undefined : args.error,
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

export const retryExtract = mutation({
  args: { captureId: v.id("captures") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const capture = await ctx.db.get("captures", args.captureId);
    if (capture === null || capture.userId !== userId) {
      throw new Error("Capture not found");
    }
    if (capture.status !== "failed") {
      throw new Error("Capture is not ready to retry");
    }
    await ctx.db.patch("captures", args.captureId, {
      status: "pending",
      error: undefined,
      errorDetail: undefined,
    });
    await ctx.scheduler.runAfter(0, internal.captures.extract, {
      captureId: args.captureId,
    });
    return null;
  },
});
