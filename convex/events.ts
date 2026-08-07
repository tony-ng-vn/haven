import { Infer, v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { internal } from "./_generated/api";
import {
  internalMutation,
  MutationCtx,
  mutation,
  query,
} from "./_generated/server";
import { requireUser } from "./authz";

const CLIENT_KEY_MAX = 128;
const TITLE_MAX = 200;
const PERSON_EVENT_LIMIT = 100;
const EVENT_LINK_DELETE_PAGE = 200;

export const eventInputValidator = v.object({
  clientKey: v.string(),
  title: v.string(),
  startedAt: v.number(),
});

export type EventInput = Infer<typeof eventInputValidator>;

const eventSummaryValidator = v.object({
  _id: v.id("events"),
  title: v.string(),
  startedAt: v.number(),
  endedAt: v.optional(v.number()),
});

function normalizeEvent(input: EventInput): EventInput {
  const clientKey = input.clientKey.trim();
  const title = input.title.trim();
  if (clientKey === "") {
    throw new Error("Event key is required");
  }
  if (clientKey.length > CLIENT_KEY_MAX) {
    throw new Error("Event key is too long");
  }
  if (title === "") {
    throw new Error("Event name is required");
  }
  if (title.length > TITLE_MAX) {
    throw new Error("Event name is too long");
  }
  return { clientKey, title, startedAt: input.startedAt };
}

export async function ensureEvent(
  ctx: MutationCtx,
  userId: string,
  input: EventInput,
): Promise<{ event: Doc<"events">; created: boolean }> {
  const normalized = normalizeEvent(input);
  const existing = await ctx.db
    .query("events")
    .withIndex("by_userId_and_clientKey", (q) =>
      q.eq("userId", userId).eq("clientKey", normalized.clientKey),
    )
    .unique();
  if (existing !== null) {
    return { event: existing, created: false };
  }
  const now = Date.now();
  const eventId = await ctx.db.insert("events", {
    userId,
    ...normalized,
    updatedAt: now,
  });
  const event = await ctx.db.get("events", eventId);
  if (event === null) {
    throw new Error("Event could not be saved");
  }
  return { event, created: true };
}

export async function linkEventPerson(
  ctx: MutationCtx,
  userId: string,
  eventId: Id<"events">,
  personId: Id<"people">,
): Promise<"linked" | "already"> {
  const existing = await ctx.db
    .query("eventPeople")
    .withIndex("by_eventId_and_personId", (q) =>
      q.eq("eventId", eventId).eq("personId", personId),
    )
    .unique();
  if (existing !== null) {
    return "already";
  }
  const event = await ctx.db.get("events", eventId);
  if (event === null || event.userId !== userId) {
    throw new Error("Event not found");
  }
  await ctx.db.insert("eventPeople", {
    userId,
    eventId,
    personId,
    eventStartedAt: event.startedAt,
    linkedAt: Date.now(),
  });
  return "linked";
}

export async function deleteEventLinksForPerson(
  ctx: MutationCtx,
  personId: Id<"people">,
): Promise<void> {
  const links = await ctx.db
    .query("eventPeople")
    .withIndex("by_personId", (q) => q.eq("personId", personId))
    .take(EVENT_LINK_DELETE_PAGE);
  for (const link of links) {
    await ctx.db.delete("eventPeople", link._id);
  }
  if (links.length === EVENT_LINK_DELETE_PAGE) {
    await ctx.scheduler.runAfter(0, internal.events.deletePersonLinksPage, {
      personId,
    });
  }
}

export const deletePersonLinksPage = internalMutation({
  args: { personId: v.id("people") },
  returns: v.null(),
  handler: async (ctx, args) => {
    await deleteEventLinksForPerson(ctx, args.personId);
    return null;
  },
});

export const upsert = mutation({
  args: {
    ...eventInputValidator.fields,
    endedAt: v.optional(v.number()),
  },
  returns: v.object({
    status: v.union(
      v.literal("created"),
      v.literal("updated"),
      v.literal("already"),
    ),
    eventId: v.id("events"),
  }),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    if (args.endedAt !== undefined && args.endedAt < args.startedAt) {
      throw new Error("Event cannot end before it starts");
    }
    const { event, created } = await ensureEvent(ctx, userId, args);
    if (created) {
      if (args.endedAt !== undefined) {
        await ctx.db.patch("events", event._id, {
          endedAt: args.endedAt,
          updatedAt: Date.now(),
        });
      }
      return { status: "created" as const, eventId: event._id };
    }
    // The lifecycle only moves forward. A delayed Start may arrive after End,
    // and a retried older End may arrive after a later one; neither can reopen
    // or shorten the span already saved.
    if (
      event.endedAt !== undefined &&
      (args.endedAt === undefined || args.endedAt <= event.endedAt)
    ) {
      return { status: "already" as const, eventId: event._id };
    }
    if (event.endedAt === args.endedAt) {
      return { status: "already" as const, eventId: event._id };
    }
    await ctx.db.patch("events", event._id, {
      endedAt: args.endedAt,
      updatedAt: Date.now(),
    });
    return { status: "updated" as const, eventId: event._id };
  },
});

export const linkPerson = mutation({
  args: {
    ...eventInputValidator.fields,
    personId: v.id("people"),
  },
  returns: v.object({
    status: v.union(v.literal("linked"), v.literal("already")),
    eventId: v.id("events"),
  }),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const person = await ctx.db.get("people", args.personId);
    if (person === null || person.userId !== userId) {
      throw new Error("Person not found");
    }
    const { event } = await ensureEvent(ctx, userId, args);
    const status = await linkEventPerson(ctx, userId, event._id, person._id);
    return { status, eventId: event._id };
  },
});

export const listForPerson = query({
  args: { personId: v.id("people") },
  returns: v.array(eventSummaryValidator),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const person = await ctx.db.get("people", args.personId);
    if (person === null || person.userId !== userId) {
      throw new Error("Person not found");
    }
    const links = await ctx.db
      .query("eventPeople")
      .withIndex("by_personId_and_eventStartedAt", (q) =>
        q.eq("personId", args.personId),
      )
      .order("desc")
      .take(PERSON_EVENT_LIMIT);
    const events = await Promise.all(
      links.map((link) => ctx.db.get("events", link.eventId)),
    );
    return events
      .filter(
        (event): event is Doc<"events"> =>
          event !== null && event.userId === userId,
      )
      .sort((a, b) => b.startedAt - a.startedAt)
      .map((event) => ({
        _id: event._id,
        title: event.title,
        startedAt: event.startedAt,
        endedAt: event.endedAt,
      }));
  },
});
