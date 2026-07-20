import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { Doc } from "./_generated/dataModel";
import { requireUser } from "./authz";
import { checkRateLimit } from "./rateLimit";

const MINUTE_MS = 60_000;
const PRESENCE_TTL_MS = 2 * MINUTE_MS;
const MAX_ACTIVE_PEERS = 40;
const MAX_MY_ROOMS = 10;
const MAX_DISPLAY_NAME_LENGTH = 40;
const ROOM_CODE_RE = /^[A-Z0-9-]{3,32}$/;

const presenceStartedValidator = v.object({
  roomCode: v.string(),
  expiresAt: v.number(),
});

const peerValidator = v.object({
  displayName: v.string(),
  lastSeenAt: v.number(),
});

function normalizeRoomCode(roomCode: string): string {
  const normalized = roomCode.trim().toUpperCase().replace(/\s+/g, "-");
  if (!ROOM_CODE_RE.test(normalized)) {
    throw new Error("Use 3-32 letters, numbers, or dashes for the room code");
  }
  return normalized;
}

function normalizeDisplayName(displayName: string | undefined): string {
  const trimmed = displayName?.trim() ?? "";
  if (trimmed === "") {
    return "Someone nearby";
  }
  return trimmed.slice(0, MAX_DISPLAY_NAME_LENGTH);
}

function projectPeer(presence: Doc<"loveAlarmPresence">) {
  return {
    displayName: presence.displayName,
    lastSeenAt: presence.lastSeenAt,
  };
}

export const startPresence = mutation({
  args: {
    roomCode: v.string(),
    displayName: v.optional(v.string()),
  },
  returns: presenceStartedValidator,
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "loveAlarm:startPresence", 20, MINUTE_MS);
    const roomCode = normalizeRoomCode(args.roomCode);
    const now = Date.now();
    const expiresAt = now + PRESENCE_TTL_MS;
    const displayName = normalizeDisplayName(args.displayName);
    const existing = await ctx.db
      .query("loveAlarmPresence")
      .withIndex("by_userId_and_roomCode", (q) =>
        q.eq("userId", userId).eq("roomCode", roomCode),
      )
      .unique();

    if (existing === null) {
      await ctx.db.insert("loveAlarmPresence", {
        userId,
        roomCode,
        displayName,
        joinedAt: now,
        lastSeenAt: now,
        expiresAt,
      });
    } else {
      await ctx.db.patch(existing._id, {
        displayName,
        lastSeenAt: now,
        expiresAt,
      });
    }

    return { roomCode, expiresAt };
  },
});

export const heartbeat = mutation({
  args: { roomCode: v.string() },
  returns: presenceStartedValidator,
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "loveAlarm:heartbeat", 120, MINUTE_MS);
    const roomCode = normalizeRoomCode(args.roomCode);
    const now = Date.now();
    const expiresAt = now + PRESENCE_TTL_MS;
    const existing = await ctx.db
      .query("loveAlarmPresence")
      .withIndex("by_userId_and_roomCode", (q) =>
        q.eq("userId", userId).eq("roomCode", roomCode),
      )
      .unique();

    if (existing === null) {
      throw new Error("Join this Love Alarm room before sending a heartbeat");
    }

    await ctx.db.patch(existing._id, { lastSeenAt: now, expiresAt });
    return { roomCode, expiresAt };
  },
});

export const stopPresence = mutation({
  args: { roomCode: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const roomCode = normalizeRoomCode(args.roomCode);
    const existing = await ctx.db
      .query("loveAlarmPresence")
      .withIndex("by_userId_and_roomCode", (q) =>
        q.eq("userId", userId).eq("roomCode", roomCode),
      )
      .unique();
    if (existing !== null) {
      await ctx.db.delete(existing._id);
    }
    return null;
  },
});

export const nearby = query({
  args: { roomCode: v.string() },
  returns: v.object({
    roomCode: v.string(),
    peers: v.array(peerValidator),
  }),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const roomCode = normalizeRoomCode(args.roomCode);
    const now = Date.now();
    const active = await ctx.db
      .query("loveAlarmPresence")
      .withIndex("by_roomCode_and_expiresAt", (q) =>
        q.eq("roomCode", roomCode).gte("expiresAt", now),
      )
      .order("desc")
      .take(MAX_ACTIVE_PEERS + 1);

    return {
      roomCode,
      peers: active
        .filter((presence) => presence.userId !== userId)
        .slice(0, MAX_ACTIVE_PEERS)
        .map(projectPeer),
    };
  },
});

export const myPresence = query({
  args: {},
  returns: v.array(
    v.object({
      roomCode: v.string(),
      displayName: v.string(),
      lastSeenAt: v.number(),
      expiresAt: v.number(),
    }),
  ),
  handler: async (ctx) => {
    const userId = await requireUser(ctx);
    const now = Date.now();
    const active = await ctx.db
      .query("loveAlarmPresence")
      .withIndex("by_userId_and_expiresAt", (q) =>
        q.eq("userId", userId).gte("expiresAt", now),
      )
      .order("desc")
      .take(MAX_MY_ROOMS);

    return active.map((presence) => ({
      roomCode: presence.roomCode,
      displayName: presence.displayName,
      lastSeenAt: presence.lastSeenAt,
      expiresAt: presence.expiresAt,
    }));
  },
});
