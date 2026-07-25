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
import { normalizeName } from "./nameSearch";

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;
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
      // Written here because this insert bypasses addPerson; without it the
      // person is invisible to the normalized search index.
      normalizedName: normalizeName(capture.extracted.name),
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

// Manual triage: when OCR/API cannot read a screenshot, the human names the
// person themselves. Allowed while the capture is "failed" or still "pending"
// -- a stuck extraction should never block a human. Deleting the capture row
// here makes any in-flight finishExtract/failExtract a harmless no-op (both
// null-guard the row), so there is no duplicate person and nothing throws.
export const acceptManualCapture = mutation({
  args: {
    captureId: v.id("captures"),
    name: v.string(),
    headline: v.optional(v.string()),
    context: v.optional(v.string()),
    link: v.optional(v.string()),
  },
  returns: v.id("people"),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    // Naming schedules a paid embedding, so guard the burst like the other
    // spend paths do -- and before the ownership check, so probing another
    // user's captures still spends the attacker's own budget.
    await checkRateLimit(ctx, userId, "acceptManual", 30, MINUTE_MS);
    const capture = await ctx.db.get("captures", args.captureId);
    if (capture === null || capture.userId !== userId) {
      throw new Error("Capture not found");
    }
    if (capture.status !== "failed" && capture.status !== "pending") {
      throw new Error("Capture is not ready");
    }
    const name = args.name.trim();
    if (name === "") {
      throw new Error("Name is required");
    }
    const personId = await ctx.db.insert("people", {
      userId,
      name,
      // Same reason as acceptCapture: search visibility requires it.
      normalizedName: normalizeName(name),
      link: args.link,
      context: args.context,
      headline: args.headline,
      // The screenshot stays with the person as a visual memory anchor.
      screenshotId: capture.screenshotId,
      updatedAt: Date.now(),
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
    // A retry re-runs the paid extraction, so it needs the same
    // denial-of-wallet guard as creating a capture in the first place.
    await checkRateLimit(ctx, userId, "retryExtract:minute", 10, MINUTE_MS);
    await checkRateLimit(ctx, userId, "retryExtract:day", 100, DAY_MS);
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

// ------------------------------------------------------------ janitor crons

// If the extract action is killed rather than throwing (a timeout, a
// redeploy mid-run), its catch block never runs and the capture stays
// "pending" forever -- an eternal skeleton card in the UI. Sweep those loose
// ends into "failed" so the existing retry/manual-naming UI takes over.
const STUCK_PENDING_MS = 15 * MINUTE_MS;
const STUCK_SWEEP_BATCH_SIZE = 100;

export const sweepStuckCaptures = internalMutation({
  args: {},
  returns: v.number(),
  handler: async (ctx) => {
    const cutoff = Date.now() - STUCK_PENDING_MS;
    const stuck = await ctx.db
      .query("captures")
      .withIndex("by_status", (q) =>
        q.eq("status", "pending").lt("_creationTime", cutoff),
      )
      .take(STUCK_SWEEP_BATCH_SIZE);
    for (const capture of stuck) {
      await ctx.db.patch("captures", capture._id, {
        status: "failed",
        error: GENERIC_ERROR_MESSAGE,
        errorDetail: "sweepStuckCaptures: pending past the stuck threshold",
      });
    }
    return stuck.length;
  },
});

// A client can upload a blob and never call createCapture (a crash, an
// abandoned tab), leaving an invisible file that nothing ever references.
// Delete those once they're old enough that no in-flight upload could still
// need them.
//
// Referenced-set construction: rather than reading captures/people in bulk
// (unsound once either table outgrows a bounded read -- a screenshotId just
// past the read window would look orphaned and get deleted), this checks
// each storage candidate against by_screenshotId, an exact indexed lookup
// on both tables. That keeps the sweep bounded (one _storage page per run)
// *and* sound at any table size: a blob is only ever deleted because both
// indexed lookups came back empty, never because a scan ran out of rows to
// check. A false-positive delete would destroy a user's screenshot, so this
// trades an extra pair of indexed reads per candidate for a hard guarantee
// instead of a probabilistic one.
const ORPHAN_AGE_MS = HOUR_MS;
const ORPHAN_SWEEP_BATCH_SIZE = 100;

export const sweepOrphanedUploads = internalMutation({
  // batchSize is for tests, which prove wall-progress with a tiny batch.
  args: { batchSize: v.optional(v.number()) },
  returns: v.number(),
  handler: async (ctx, args) => {
    const batchSize = args.batchSize ?? ORPHAN_SWEEP_BATCH_SIZE;
    const cutoff = Date.now() - ORPHAN_AGE_MS;
    // Resume from the persisted watermark: referenced blobs are skipped,
    // never deleted, so without a cursor they would wall off the head of
    // the oldest-first scan and orphans behind them would leak forever.
    const state = await ctx.db
      .query("sweepState")
      .withIndex("by_key", (q) => q.eq("key", "orphanSweep"))
      .unique();
    const watermark = state?.watermark ?? 0;
    const candidates = await ctx.db.system
      .query("_storage")
      .order("asc")
      .filter((q) =>
        q.and(
          q.gt(q.field("_creationTime"), watermark),
          q.lt(q.field("_creationTime"), cutoff),
        ),
      )
      .take(batchSize);
    let deleted = 0;
    for (const file of candidates) {
      const referencingCapture = await ctx.db
        .query("captures")
        .withIndex("by_screenshotId", (q) => q.eq("screenshotId", file._id))
        .first();
      if (referencingCapture !== null) {
        continue;
      }
      const referencingPerson = await ctx.db
        .query("people")
        .withIndex("by_screenshotId", (q) => q.eq("screenshotId", file._id))
        .first();
      if (referencingPerson !== null) {
        continue;
      }
      const referencingProfile = await ctx.db
        .query("profiles")
        .withIndex("by_photoStorageId", (q) =>
          q.eq("photoStorageId", file._id),
        )
        .first();
      if (referencingProfile !== null) {
        continue;
      }
      await ctx.storage.delete(file._id);
      deleted++;
    }
    // A full batch means there may be more beyond it: advance the cursor.
    // A short batch means this cycle reached the end: reset to the start
    // so the next cycle rescans everything (catching newly aged orphans).
    const nextWatermark =
      candidates.length < batchSize
        ? 0
        : candidates[candidates.length - 1]._creationTime;
    if (state === null) {
      await ctx.db.insert("sweepState", {
        key: "orphanSweep",
        watermark: nextWatermark,
      });
    } else {
      await ctx.db.patch("sweepState", state._id, { watermark: nextWatermark });
    }
    return deleted;
  },
});
