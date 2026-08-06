import {
  internalAction,
  internalMutation,
  internalQuery,
  mutation,
  query,
} from "./_generated/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import { MutationCtx } from "./_generated/server";
import { Doc, Id } from "./_generated/dataModel";
import { extractProfile } from "./openaiClient";
import { requireUser } from "./authz";
import { checkRateLimit } from "./rateLimit";
import { normalizeName, personSearchText } from "./nameSearch";
import { contactHandleValidator, HandleSource } from "./peopleFields";
import {
  handleDisplayValue,
  handleIndexKeys,
  hasPhoneDigit,
  isPhoneNumberPlatform,
} from "./handleKeys";
import { requireImageBlob } from "./imageBlobs";
import { syncMemories } from "./memories";
import {
  appendContext,
  ContactHandleInput,
  deletePersonHandles,
  findHandleOwner,
  insertPersonHandles,
  mergeHandleIntoOwner,
  withAddedAt,
} from "./people";

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;
const DAY_MS = 24 * HOUR_MS;

const extractedValidator = v.object({
  platform: v.string(),
  name: v.string(),
  handle: v.optional(v.string()),
  headline: v.optional(v.string()),
  bio: v.optional(v.string()),
});

// The one place both accept paths fold a platform and a handle into the
// shape people.contactHandles stores: display value on the row, index keys on
// personHandles, folded by the shared seam so a screenshot and a share of the
// same account can never land on two people. extra carries provenance the
// caller already knows (acceptCapture always says "imported"; a caller-typed
// platformId passes through) -- foldContactHandle folds the value, it does
// not decide where the handle came from.
function foldContactHandle(
  platform: string,
  handle: string,
  extra?: { source?: HandleSource; platformId?: string },
): ContactHandleInput | undefined {
  const folded = handleIndexKeys({ platform, value: handle });
  if (folded.platform === "" || folded.valueKey === "") {
    return undefined;
  }
  return {
    platform: folded.platform,
    value: handleDisplayValue(handle),
    source: extra?.source,
    platformId: extra?.platformId,
  };
}

// What an attach can add to an owner that a straight create would have
// stored directly -- headline, bio, link and the screenshot this capture
// proves. Fill-if-empty, never overwrite: the owner's own words about
// themselves (or a previous capture's) win over whatever a new, unrelated
// screenshot happened to say.
type FillIfEmpty = {
  headline?: string;
  bio?: string;
  link?: string;
  screenshotId?: Id<"_storage">;
};

function fillEmptyFields(
  owner: Doc<"people">,
  fill: FillIfEmpty,
): Partial<Doc<"people">> {
  const fields: Partial<Doc<"people">> = {};
  if (fill.headline !== undefined && (owner.headline ?? "") === "") {
    fields.headline = fill.headline;
  }
  if (fill.bio !== undefined && (owner.bio ?? "") === "") {
    fields.bio = fill.bio;
  }
  if (fill.link !== undefined && (owner.link ?? "") === "") {
    fields.link = fill.link;
  }
  // An owner who already has a screenshot keeps it -- this capture's own
  // blob legitimately orphans here, and sweepOrphanedUploads reclaims it
  // the same way it reclaims any other blob nothing ends up pointing at.
  if (fill.screenshotId !== undefined && owner.screenshotId === undefined) {
    fields.screenshotId = fill.screenshotId;
  }
  return fields;
}

// Attaches this capture's handle to whoever already owns it instead of
// making them a second person for the same account -- the gap flagged
// against captures.ts in the identity brief: addPerson, editPerson and
// saveSharedProfile all check ownership before writing, and this pipeline
// was the one write path left that did not. Returns null when nobody owns
// the handle yet, which is the caller's signal to fall through and create.
// Deletes the capture row on a match, the same as every create path does,
// so a merged capture cannot be replayed.
//
// A refused merge returns "conflict" rather than null: the id says this
// capture is `owner`, but the value it carries already, provably, belongs to
// somebody else. null used to be the answer here too, and the caller could
// not tell "nobody owns this yet, safe to create" apart from "somebody
// disputes this" -- which minted a third person carrying owner's id and the
// conflicting value, double-indexing the value's real owner. The capture row
// is left alone on this branch (not deleted): a human can resolve it later,
// and a retry never redrains into the same corruption.
async function tryAttachToOwner(
  ctx: MutationCtx,
  userId: string,
  captureId: Id<"captures">,
  contactHandle: ContactHandleInput | undefined,
  context: string | undefined,
  fillIfEmpty: FillIfEmpty,
): Promise<
  | {
      status: "attached" | "already";
      personId: Id<"people">;
      noteTruncated: boolean;
      handleDropped: boolean;
    }
  | { status: "conflict"; personId: Id<"people"> }
  | null
> {
  if (contactHandle === undefined) {
    return null;
  }
  const keys = handleIndexKeys(contactHandle);
  const owner = await findHandleOwner(
    ctx,
    userId,
    keys.platform,
    keys.valueKey,
    contactHandle.platformId,
  );
  if (owner === null) {
    return null;
  }
  const merged = await mergeHandleIntoOwner(
    ctx,
    userId,
    owner,
    owner.contactHandles ?? [],
    contactHandle,
  );
  if (merged.status === "refused") {
    // The id says this is `owner`; the value this capture carries already
    // belongs to somebody else. Nobody is present to resolve that (this
    // pipeline runs from a screenshot or a queued replay), so this refuses
    // -- same shape as saveSharedProfile's own conflict outcome -- rather
    // than guess who is right by creating a third person or overwriting
    // either side's handle.
    return { status: "conflict", personId: owner._id };
  }
  const fields: Partial<Doc<"people">> = fillEmptyFields(owner, fillIfEmpty);
  const { context: nextContext, noteTruncated } = appendContext(
    owner.context,
    context,
  );
  if (nextContext !== owner.context) {
    fields.context = nextContext;
  }
  if (merged.changed) {
    fields.contactHandles = merged.handles;
  }
  if (Object.keys(fields).length > 0) {
    const now = Date.now();
    await ctx.db.patch("people", owner._id, {
      ...fields,
      searchText: personSearchText({ ...owner, ...fields }),
      updatedAt: now,
    });
    if (merged.changed) {
      await deletePersonHandles(ctx, owner._id);
      await insertPersonHandles(ctx, userId, owner._id, merged.handles);
    }
    await syncMemories(ctx, {
      userId,
      personId: owner._id,
      context: fields.context,
      createdAt: now,
    });
    await ctx.scheduler.runAfter(0, internal.people.embed, {
      personId: owner._id,
    });
  }
  await ctx.db.delete("captures", captureId);
  return {
    status: Object.keys(fields).length > 0 ? "attached" : "already",
    personId: owner._id,
    noteTruncated,
    handleDropped: merged.handleDropped,
  };
}

// noteTruncated mirrors addPerson's attach outcome; a straight create can
// never truncate a note captures.ts never validates the length of. handleDropped
// on "created" is narrower than the attach paths' meaning of the same field
// (there it is the 8-handle cap; here it can only be acceptCapture's own
// digitless-phone drop, since a create's array holds at most one handle) --
// same field name because both answer the same client-facing question: was
// there a handle this save could not keep.
const captureAcceptReturns = v.union(
  v.object({
    status: v.literal("created"),
    personId: v.id("people"),
    handleDropped: v.boolean(),
  }),
  v.object({
    status: v.literal("attached"),
    personId: v.id("people"),
    noteTruncated: v.boolean(),
    handleDropped: v.boolean(),
  }),
  v.object({
    status: v.literal("already"),
    personId: v.id("people"),
    noteTruncated: v.boolean(),
    handleDropped: v.boolean(),
  }),
  // Nothing is written on this branch (see tryAttachToOwner above): personId
  // names who the id says this capture is, not the value's actual owner --
  // the same "id-matched owner" convention saveSharedProfile's own conflict
  // outcome uses. The capture stays in triage for a human to resolve.
  v.object({ status: v.literal("conflict"), personId: v.id("people") }),
);

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

    await requireImageBlob(
      ctx,
      args.screenshotId,
      "Please upload an image under 10 MB",
    );

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
  returns: captureAcceptReturns,
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const capture = await ctx.db.get("captures", args.captureId);
    if (capture === null || capture.userId !== userId) {
      throw new Error("Capture not found");
    }
    if (capture.status !== "ready" || capture.extracted === undefined) {
      throw new Error("Capture is not ready");
    }
    // Lenient on purpose, unlike acceptManualCapture below: the model answers
    // with nobody present, and a screenshot showing no handle is honestly a
    // name-only person rather than a failed capture. Always "imported": OCR
    // read this off a screenshot, nobody typed or proved it.
    //
    // A digitless phone/whatsapp read ("unknown", an OCR miss) is dropped
    // rather than folded: nobody is present to fix it, so this can only
    // refuse the identity-critical contactHandles/personHandles write, not
    // throw. The raw text still lands on the legacy platform/handle scalars
    // below, same as any other extraction the fold below cannot use.
    const handleDropped =
      capture.extracted.handle !== undefined &&
      isPhoneNumberPlatform(capture.extracted.platform) &&
      !hasPhoneDigit(capture.extracted.handle);
    const contactHandle =
      capture.extracted.handle === undefined || handleDropped
        ? undefined
        : foldContactHandle(capture.extracted.platform, capture.extracted.handle, {
            source: "imported",
          });

    const attached = await tryAttachToOwner(
      ctx,
      userId,
      args.captureId,
      contactHandle,
      args.context,
      {
        headline: capture.extracted.headline,
        bio: capture.extracted.bio,
        link: args.link,
        screenshotId: capture.screenshotId,
      },
    );
    if (attached !== null) {
      return attached;
    }

    const contactHandles =
      contactHandle === undefined ? undefined : [withAddedAt([], contactHandle)];
    // X2a: a dropped handle is dropped everywhere, not just from
    // contactHandles/personHandles -- the legacy platform/handle scalars
    // are exactly what backfillLegacyHandles (people.ts) later reads to
    // fold into that same index. Writing the digitless value there anyway
    // would let that maintenance path recreate the collision this gate
    // exists to prevent, through a different write entirely.
    const legacyPlatform = handleDropped ? undefined : capture.extracted.platform;
    const legacyHandle = handleDropped ? undefined : capture.extracted.handle;
    const now = Date.now();
    const personId = await ctx.db.insert("people", {
      userId,
      name: capture.extracted.name,
      // Written here because this insert bypasses addPerson; without these
      // the person is invisible to the name and keyword search indexes.
      normalizedName: normalizeName(capture.extracted.name),
      searchText: personSearchText({
        name: capture.extracted.name,
        headline: capture.extracted.headline,
        bio: capture.extracted.bio,
        handle: legacyHandle,
        contactHandles,
        context: args.context,
      }),
      link: args.link,
      context: args.context,
      updatedAt: now,
      platform: legacyPlatform,
      handle: legacyHandle,
      headline: capture.extracted.headline,
      bio: capture.extracted.bio,
      contactHandles,
      // The screenshot stays with the person as a visual memory anchor.
      screenshotId: capture.screenshotId,
    });
    if (contactHandles !== undefined) {
      await insertPersonHandles(ctx, userId, personId, contactHandles);
    }
    await syncMemories(ctx, {
      userId,
      personId,
      context: args.context,
      createdAt: now,
    });
    await ctx.db.delete("captures", args.captureId);
    await ctx.scheduler.runAfter(0, internal.people.embed, { personId });
    return { status: "created" as const, personId, handleDropped };
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
    // One object rather than two loose fields, so a platform can never
    // arrive without the handle it names. Omitted means the human saw no
    // handle to type, which is a name-only person.
    contactHandle: v.optional(contactHandleValidator),
  },
  returns: captureAcceptReturns,
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
    // Strict where acceptCapture is lenient: the human is at the keyboard, so
    // a blank half of a typed handle is a client bug worth surfacing rather
    // than input to silently drop. Same wording as the other handle paths.
    let contactHandle: ContactHandleInput | undefined;
    if (args.contactHandle !== undefined) {
      if (args.contactHandle.platform.trim() === "") {
        throw new Error("A platform cannot be blank");
      }
      if (handleDisplayValue(args.contactHandle.value) === "") {
        throw new Error("A handle cannot be blank");
      }
      // Same refusal as people.ts's validateContactHandles, for the same
      // reason: a digitless phone/whatsapp value folds to a plain lowercase
      // string, and two different unreadable entries could otherwise
      // collide. The human is present here, so this throws instead of the
      // silent drop acceptCapture's OCR path uses below.
      if (
        isPhoneNumberPlatform(args.contactHandle.platform) &&
        !hasPhoneDigit(args.contactHandle.value)
      ) {
        throw new Error("A phone number needs at least one digit");
      }
      // A human is typing this at triage, not a form asking for identity
      // (addPerson/editPerson) -- but it is still hand-entered, so "typed"
      // is the same default those default to when the caller sends nothing.
      contactHandle = foldContactHandle(
        args.contactHandle.platform,
        args.contactHandle.value,
        {
          source: args.contactHandle.source ?? "typed",
          platformId: args.contactHandle.platformId,
        },
      );
    }

    const attached = await tryAttachToOwner(
      ctx,
      userId,
      args.captureId,
      contactHandle,
      args.context,
      // No bio field on this form -- a human at triage is not asked for one.
      { headline: args.headline, link: args.link, screenshotId: capture.screenshotId },
    );
    if (attached !== null) {
      return attached;
    }

    const contactHandles =
      contactHandle === undefined ? undefined : [withAddedAt([], contactHandle)];
    const now = Date.now();
    const personId = await ctx.db.insert("people", {
      userId,
      name,
      // Same reason as acceptCapture: search visibility requires it.
      normalizedName: normalizeName(name),
      searchText: personSearchText({
        name,
        headline: args.headline,
        contactHandles,
        context: args.context,
      }),
      link: args.link,
      context: args.context,
      headline: args.headline,
      contactHandles,
      // The screenshot stays with the person as a visual memory anchor.
      screenshotId: capture.screenshotId,
      updatedAt: now,
    });
    if (contactHandles !== undefined) {
      await insertPersonHandles(ctx, userId, personId, contactHandles);
    }
    await syncMemories(ctx, {
      userId,
      personId,
      context: args.context,
      createdAt: now,
    });
    await ctx.db.delete("captures", args.captureId);
    await ctx.scheduler.runAfter(0, internal.people.embed, { personId });
    // Never true here: a digitless phone/whatsapp value throws above rather
    // than reaching this insert (the human is present to fix it), unlike
    // acceptCapture's own lenient drop.
    return { status: "created" as const, personId, handleDropped: false };
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
      const referencingPersonPhoto = await ctx.db
        .query("people")
        .withIndex("by_photoStorageId", (q) => q.eq("photoStorageId", file._id))
        .first();
      if (referencingPersonPhoto !== null) {
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
