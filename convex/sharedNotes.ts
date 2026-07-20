import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { MutationCtx, QueryCtx, mutation, query } from "./_generated/server";
import { requireUser } from "./authz";
import { checkRateLimit } from "./rateLimit";

const MINUTE_MS = 60_000;
const MAX_SHARED_NOTE_LENGTH = 4000;
const SHARED_NOTE_TOO_LONG_ERROR =
  "Shared note is too long -- keep it under 4000 characters";

const sharedNoteValidator = v.object({
  connectionId: v.id("connections"),
  content: v.optional(v.string()),
  updatedAt: v.optional(v.number()),
  updatedByMe: v.boolean(),
});

type ResolvedConnection = {
  connection: Doc<"connections">;
};

async function resolveConnectedPerson(
  ctx: QueryCtx | MutationCtx,
  userId: string,
  personId: Id<"people">,
): Promise<ResolvedConnection | null> {
  const person = await ctx.db.get("people", personId);
  if (person === null || person.userId !== userId) {
    return null;
  }

  const asA = await ctx.db
    .query("connections")
    .withIndex("by_userAId_and_personAId", (q) =>
      q.eq("userAId", userId).eq("personAId", personId),
    )
    .unique();
  if (asA !== null && (await reciprocalPersonStillMatches(ctx, asA, "A"))) {
    return { connection: asA };
  }

  const asB = await ctx.db
    .query("connections")
    .withIndex("by_userBId_and_personBId", (q) =>
      q.eq("userBId", userId).eq("personBId", personId),
    )
    .unique();
  if (asB !== null && (await reciprocalPersonStillMatches(ctx, asB, "B"))) {
    return { connection: asB };
  }

  return null;
}

async function reciprocalPersonStillMatches(
  ctx: QueryCtx | MutationCtx,
  connection: Doc<"connections">,
  currentSide: "A" | "B",
): Promise<boolean> {
  const otherPersonId =
    currentSide === "A" ? connection.personBId : connection.personAId;
  const otherUserId = currentSide === "A" ? connection.userBId : connection.userAId;
  const otherPerson = await ctx.db.get("people", otherPersonId);
  return otherPerson !== null && otherPerson.userId === otherUserId;
}

export const getForPerson = query({
  args: { personId: v.id("people") },
  returns: v.union(v.null(), sharedNoteValidator),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const resolved = await resolveConnectedPerson(ctx, userId, args.personId);
    if (resolved === null) {
      return null;
    }

    const note = await ctx.db
      .query("sharedNotes")
      .withIndex("by_connectionId", (q) =>
        q.eq("connectionId", resolved.connection._id),
      )
      .unique();
    if (note === null) {
      return {
        connectionId: resolved.connection._id,
        updatedByMe: false,
      };
    }

    return {
      connectionId: resolved.connection._id,
      content: note.content,
      updatedAt: note.updatedAt,
      updatedByMe: note.updatedByUserId === userId,
    };
  },
});

export const updateForPerson = mutation({
  args: { personId: v.id("people"), content: v.optional(v.string()) },
  returns: v.null(),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "updateSharedNote", 60, MINUTE_MS);

    const resolved = await resolveConnectedPerson(ctx, userId, args.personId);
    if (resolved === null) {
      throw new Error("Mutual connection not found");
    }

    const content =
      args.content === undefined || args.content.trim() === ""
        ? undefined
        : args.content.trim();
    if (content !== undefined && content.length > MAX_SHARED_NOTE_LENGTH) {
      throw new Error(SHARED_NOTE_TOO_LONG_ERROR);
    }

    const existing = await ctx.db
      .query("sharedNotes")
      .withIndex("by_connectionId", (q) =>
        q.eq("connectionId", resolved.connection._id),
      )
      .unique();
    const now = Date.now();

    if (existing === null) {
      if (content !== undefined) {
        await ctx.db.insert("sharedNotes", {
          connectionId: resolved.connection._id,
          content,
          updatedAt: now,
          updatedByUserId: userId,
        });
      }
      return null;
    }

    await ctx.db.patch("sharedNotes", existing._id, {
      content,
      updatedAt: now,
      updatedByUserId: userId,
    });
    return null;
  },
});
