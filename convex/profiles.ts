import { mutation, query, MutationCtx } from "./_generated/server";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import { requireUser } from "./authz";
import { checkRateLimit } from "./rateLimit";
import { normalizeName } from "./nameSearch";

const MINUTE_MS = 60_000;

const USERNAME_PATTERN = /^[a-z0-9_]{3,24}$/;
const USERNAME_HELP =
  "Use 3-24 lowercase letters, numbers, or underscores";

const myProfileValidator = v.object({
  _id: v.id("profiles"),
  _creationTime: v.number(),
  username: v.string(),
  updatedAt: v.number(),
});

const publicProfileValidator = v.object({
  username: v.string(),
});

function normalizeUsername(raw: string): string {
  return raw.trim().replace(/^@+/, "").toLowerCase();
}

function validateUsername(raw: string): string {
  const username = normalizeUsername(raw);
  if (!USERNAME_PATTERN.test(username)) {
    throw new Error(USERNAME_HELP);
  }
  return username;
}

async function getProfileByUser(ctx: MutationCtx, userId: string) {
  return await ctx.db
    .query("profiles")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .unique();
}

async function ensureMeetPerson(args: {
  ctx: MutationCtx;
  ownerUserId: string;
  contactUserId: string;
  contactUsername: string;
  now: number;
}): Promise<Id<"people">> {
  const existing = await args.ctx.db
    .query("people")
    .withIndex("by_user_and_havenContactUserId", (q) =>
      q
        .eq("userId", args.ownerUserId)
        .eq("havenContactUserId", args.contactUserId),
    )
    .unique();
  if (existing !== null) {
    return existing._id;
  }

  const displayName = `@${args.contactUsername}`;
  const personId = await args.ctx.db.insert("people", {
    userId: args.ownerUserId,
    name: displayName,
    normalizedName: normalizeName(args.contactUsername),
    context: "Met in person through Haven Meet.",
    updatedAt: args.now,
    platform: "Haven",
    handle: args.contactUsername,
    havenContactUserId: args.contactUserId,
  });
  await args.ctx.scheduler.runAfter(0, internal.people.embed, { personId });
  return personId;
}

export const getMyProfile = query({
  args: {},
  returns: v.union(v.null(), myProfileValidator),
  handler: async (ctx) => {
    const userId = await requireUser(ctx);
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .unique();
    if (profile === null) {
      return null;
    }
    return {
      _id: profile._id,
      _creationTime: profile._creationTime,
      username: profile.username,
      updatedAt: profile.updatedAt,
    };
  },
});

export const setUsername = mutation({
  args: { username: v.string() },
  returns: myProfileValidator,
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "setUsername", 10, MINUTE_MS);
    const username = validateUsername(args.username);
    const taken = await ctx.db
      .query("profiles")
      .withIndex("by_username", (q) => q.eq("username", username))
      .unique();
    if (taken !== null && taken.userId !== userId) {
      throw new Error("That username is already taken");
    }

    const now = Date.now();
    const existing = await getProfileByUser(ctx, userId);
    if (existing === null) {
      const profileId = await ctx.db.insert("profiles", {
        userId,
        username,
        updatedAt: now,
      });
      const profile = await ctx.db.get(profileId);
      if (profile === null) {
        throw new Error("Could not create profile");
      }
      return {
        _id: profile._id,
        _creationTime: profile._creationTime,
        username: profile.username,
        updatedAt: profile.updatedAt,
      };
    }

    await ctx.db.patch("profiles", existing._id, { username, updatedAt: now });
    return {
      _id: existing._id,
      _creationTime: existing._creationTime,
      username,
      updatedAt: now,
    };
  },
});

export const lookupByUsername = query({
  args: { username: v.string() },
  returns: v.union(v.null(), publicProfileValidator),
  handler: async (ctx, args) => {
    await requireUser(ctx);
    const username = normalizeUsername(args.username);
    if (!USERNAME_PATTERN.test(username)) {
      return null;
    }
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_username", (q) => q.eq("username", username))
      .unique();
    if (profile === null) {
      return null;
    }
    return { username: profile.username };
  },
});

export const meetExchange = mutation({
  args: { username: v.string() },
  returns: v.object({
    personId: v.id("people"),
    peerUsername: v.string(),
  }),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "meetExchange", 20, MINUTE_MS);
    const myProfile = await getProfileByUser(ctx, userId);
    if (myProfile === null) {
      throw new Error("Choose your Haven username first");
    }

    const username = validateUsername(args.username);
    const peerProfile = await ctx.db
      .query("profiles")
      .withIndex("by_username", (q) => q.eq("username", username))
      .unique();
    if (peerProfile === null) {
      throw new Error("No Haven profile found for that username");
    }
    if (peerProfile.userId === userId) {
      throw new Error("Enter the other person's username");
    }

    const now = Date.now();
    const personId = await ensureMeetPerson({
      ctx,
      ownerUserId: userId,
      contactUserId: peerProfile.userId,
      contactUsername: peerProfile.username,
      now,
    });
    await ensureMeetPerson({
      ctx,
      ownerUserId: peerProfile.userId,
      contactUserId: userId,
      contactUsername: myProfile.username,
      now,
    });

    return { personId, peerUsername: peerProfile.username };
  },
});
