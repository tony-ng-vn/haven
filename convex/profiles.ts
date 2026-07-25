import { mutation, query, MutationCtx, QueryCtx } from "./_generated/server";
import { Infer, v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import { requireUser } from "./authz";
import { checkRateLimit } from "./rateLimit";
import { normalizeName } from "./nameSearch";
import {
  cityInputValidator,
  cityValidator,
  handleValidator,
  platformValidator,
  publicHandleValidator,
} from "./profileFields";

const MINUTE_MS = 60_000;
const MAX_PHOTO_BYTES = 10 * 1024 * 1024;

const USERNAME_MAX_LENGTH = 24;
const USERNAME_PATTERN = /^[a-z0-9_]{3,24}$/;
const USERNAME_HELP =
  "Use 3-24 lowercase letters, numbers, or underscores";

const myProfileValidator = v.object({
  _id: v.id("profiles"),
  _creationTime: v.number(),
  username: v.string(),
  updatedAt: v.number(),
});

// The caller's own card. userId is deliberately absent: it is the Clerk
// identity key, and no client has a reason to read it back.
const myCardValidator = v.object({
  _id: v.id("profiles"),
  _creationTime: v.number(),
  username: v.string(),
  updatedAt: v.number(),
  name: v.optional(v.string()),
  photoStorageId: v.optional(v.id("_storage")),
  city: v.optional(cityValidator),
  handles: v.optional(v.array(handleValidator)),
  primaryPlatform: v.optional(platformValidator),
  company: v.optional(v.string()),
  role: v.optional(v.string()),
});

const publicProfileValidator = v.object({
  username: v.string(),
});

const claimHandleValidator = v.object({
  status: v.union(v.literal("claimed"), v.literal("taken")),
  handle: v.string(),
  suggestions: v.array(v.string()),
});

// The public web card at inhavens.com/<handle>. `handles` is typed with
// publicHandleValidator, which has no "phone" member, so Convex's own return
// validation makes a leaked phone number structurally impossible rather than
// merely unlikely. City reuses cityInputValidator because that is exactly the
// visitor-facing shape: our Phase 3 `normalized` filter key stays private.
const publicCardValidator = v.object({
  handle: v.string(),
  name: v.string(),
  photoUrl: v.union(v.null(), v.string()),
  city: v.optional(cityInputValidator),
  handles: v.array(publicHandleValidator),
  // Can name a platform whose handle was stripped above (phone), which is the
  // point: the page shows a Connect call to action instead of a number. So a
  // reader must not assume this points at an entry in `handles`.
  primaryPlatform: v.optional(platformValidator),
});

type CardFields = Partial<
  Omit<
    Doc<"profiles">,
    "_id" | "_creationTime" | "userId" | "username" | "updatedAt"
  >
>;

type CityInput = Infer<typeof cityInputValidator>;
type HandleInput = Infer<typeof handleValidator>;
type PublicHandle = Infer<typeof publicHandleValidator>;

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

async function getProfileByUser(ctx: QueryCtx | MutationCtx, userId: string) {
  return await ctx.db
    .query("profiles")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .unique();
}

async function getProfileByUsername(ctx: QueryCtx, username: string) {
  return await ctx.db
    .query("profiles")
    .withIndex("by_username", (q) => q.eq("username", username))
    .unique();
}

function requireText(label: string, raw: string): string {
  const value = raw.trim();
  if (value === "") {
    throw new Error(`${label} cannot be blank`);
  }
  return value;
}

function withCityKey(city: CityInput) {
  const name = requireText("City", city.name);
  return { ...city, name, normalized: normalizeName(name) };
}

function validateHandles(handles: HandleInput[]): HandleInput[] {
  const seen = new Set<string>();
  return handles.map((handle) => {
    // primaryPlatform points at a platform, not at a row, so a second handle
    // on the same platform would make that pointer ambiguous.
    if (seen.has(handle.platform)) {
      throw new Error("Keep one handle per platform");
    }
    seen.add(handle.platform);
    return {
      platform: handle.platform,
      value: requireText("A handle", handle.value),
      verified: handle.verified,
    };
  });
}

// Never trust the client's claim about what it uploaded, and drop a blob that
// fails validation -- same reasoning as createCapture in captures.ts.
async function requirePhotoBlob(ctx: MutationCtx, photoStorageId: Id<"_storage">) {
  const meta = await ctx.db.system.get("_storage", photoStorageId);
  const isValidImage =
    meta !== null &&
    meta.contentType !== undefined &&
    meta.contentType.startsWith("image/") &&
    meta.size <= MAX_PHOTO_BYTES;
  if (!isValidImage) {
    if (meta !== null) {
      await ctx.storage.delete(photoStorageId);
    }
    throw new Error("Please choose an image under 10 MB");
  }
}

const HANDLE_SUFFIX_TRIES = 10;
const HANDLE_SUGGESTIONS = 3;

// Address ladder for a name: bare first name, then first_last, then a short
// numeric suffix. Underscore rather than hyphen because USERNAME_PATTERN --
// shared with the legacy setUsername path -- allows only a-z, 0-9 and "_".
function handleCandidates(name: string): string[] {
  const parts = normalizeName(name)
    .split(" ")
    .map((part) => part.replace(/[^a-z0-9]/g, ""))
    .filter((part) => part !== "");
  // A name with no Latin characters at all still deserves an address, so fall
  // back to a generic base instead of failing the claim.
  const first = parts[0] ?? "haven";
  const base =
    parts.length > 1 ? `${first}_${parts[parts.length - 1]}` : first;
  const ladder = [first, base];
  for (let n = 2; n < 2 + HANDLE_SUFFIX_TRIES; n++) {
    const suffix = String(n);
    ladder.push(base.slice(0, USERNAME_MAX_LENGTH - suffix.length) + suffix);
  }
  return [
    ...new Set(ladder.map((candidate) => candidate.slice(0, USERNAME_MAX_LENGTH))),
  ].filter((candidate) => USERNAME_PATTERN.test(candidate));
}

async function freeCandidates(
  ctx: MutationCtx,
  name: string,
  limit: number,
): Promise<string[]> {
  const free: string[] = [];
  for (const candidate of handleCandidates(name)) {
    if ((await getProfileByUsername(ctx, candidate)) === null) {
      free.push(candidate);
      if (free.length === limit) {
        break;
      }
    }
  }
  return free;
}

async function mintHandle(ctx: MutationCtx, name: string): Promise<string> {
  const free = await freeCandidates(ctx, name, 1);
  if (free.length === 0) {
    throw new Error("Could not pick an address for you -- choose one yourself");
  }
  return free[0];
}

function toMyCard(profile: Doc<"profiles">) {
  return {
    _id: profile._id,
    _creationTime: profile._creationTime,
    username: profile.username,
    updatedAt: profile.updatedAt,
    name: profile.name,
    photoStorageId: profile.photoStorageId,
    city: profile.city,
    handles: profile.handles,
    primaryPlatform: profile.primaryPlatform,
    company: profile.company,
    role: profile.role,
  };
}

// Phone is dropped rather than masked: an entry that carries a number never
// reaches the public shape at all.
function toPublicHandles(handles: HandleInput[] | undefined): PublicHandle[] {
  return (handles ?? []).filter(
    (handle): handle is PublicHandle => handle.platform !== "phone",
  );
}

async function toPublicCard(ctx: QueryCtx, profile: Doc<"profiles">) {
  // A row claimed by the legacy web flow has no card yet, and an empty card
  // page is worse than a plain "no such person".
  if (profile.name === undefined) {
    return null;
  }
  return {
    handle: profile.username,
    name: profile.name,
    photoUrl:
      profile.photoStorageId === undefined
        ? null
        : await ctx.storage.getUrl(profile.photoStorageId),
    city:
      profile.city === undefined
        ? undefined
        : {
            name: profile.city.name,
            admin: profile.city.admin,
            country: profile.city.country,
          },
    handles: toPublicHandles(profile.handles),
    primaryPlatform: profile.primaryPlatform,
  };
}

// A Convex patch treats an explicit undefined as "delete this field", so the
// insert path has to drop the keys a null-clear left behind.
function definedFields(fields: CardFields): CardFields {
  return Object.fromEntries(
    Object.entries(fields).filter(([, value]) => value !== undefined),
  ) as CardFields;
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

// The caller's whole card. Onboarding resumes at the first unanswered question,
// and the client works that out from this, not from a local counter: a counter
// is lost on reinstall and lies after an edit on another device.
export const getMyCard = query({
  args: {},
  returns: v.union(v.null(), myCardValidator),
  handler: async (ctx) => {
    const userId = await requireUser(ctx);
    const profile = await getProfileByUser(ctx, userId);
    return profile === null ? null : toMyCard(profile);
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

export const updateMyProfile = mutation({
  // An omitted field is left alone; an explicit null clears it. Name is the
  // one field with no null: a card without a name has nothing to show.
  args: {
    name: v.optional(v.string()),
    photoStorageId: v.optional(v.union(v.id("_storage"), v.null())),
    city: v.optional(v.union(cityInputValidator, v.null())),
    handles: v.optional(v.array(handleValidator)),
    primaryPlatform: v.optional(v.union(platformValidator, v.null())),
    company: v.optional(v.union(v.string(), v.null())),
    role: v.optional(v.union(v.string(), v.null())),
  },
  returns: myCardValidator,
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "updateMyProfile", 60, MINUTE_MS);
    const existing = await getProfileByUser(ctx, userId);

    const fields: CardFields = {};
    if (args.name !== undefined) {
      const name = args.name.trim();
      if (name === "") {
        throw new Error("Enter your name");
      }
      fields.name = name;
    }
    if (args.photoStorageId !== undefined) {
      if (args.photoStorageId !== null) {
        await requirePhotoBlob(ctx, args.photoStorageId);
      }
      fields.photoStorageId = args.photoStorageId ?? undefined;
    }
    if (args.city !== undefined) {
      fields.city = args.city === null ? undefined : withCityKey(args.city);
    }
    if (args.handles !== undefined) {
      fields.handles = validateHandles(args.handles);
    }
    if (args.company !== undefined) {
      fields.company =
        args.company === null ? undefined : requireText("Company", args.company);
    }
    if (args.role !== undefined) {
      fields.role =
        args.role === null ? undefined : requireText("Role", args.role);
    }

    // The primary platform must point at a handle that exists once this write
    // lands, so it is checked against the merged list, not the arguments.
    const nextHandles = fields.handles ?? existing?.handles ?? [];
    const stillHeld = (platform: string) =>
      nextHandles.some((handle) => handle.platform === platform);
    if (args.primaryPlatform !== undefined) {
      if (args.primaryPlatform !== null && !stillHeld(args.primaryPlatform)) {
        throw new Error("Choose a primary platform you have a handle for");
      }
      fields.primaryPlatform = args.primaryPlatform ?? undefined;
    } else if (
      existing?.primaryPlatform !== undefined &&
      !stillHeld(existing.primaryPlatform)
    ) {
      // Deleting the primary handle clears the pointer instead of dangling it.
      fields.primaryPlatform = undefined;
    }

    const now = Date.now();
    if (existing === null) {
      const name = fields.name;
      if (name === undefined) {
        throw new Error("Enter your name first");
      }
      // Silent auto-claim: the row cannot exist without a username, and the
      // beacon address is one less onboarding question this way. The person
      // can pick a different one later with claimHandle.
      const username = await mintHandle(ctx, name);
      const profileId = await ctx.db.insert("profiles", {
        ...definedFields(fields),
        userId,
        username,
        name,
        updatedAt: now,
      });
      const created = await ctx.db.get("profiles", profileId);
      if (created === null) {
        throw new Error("Could not create profile");
      }
      return toMyCard(created);
    }

    await ctx.db.patch("profiles", existing._id, { ...fields, updatedAt: now });
    const updated = await ctx.db.get("profiles", existing._id);
    if (updated === null) {
      throw new Error("Could not save profile");
    }
    return toMyCard(updated);
  },
});

// The beacon address, claimed from the app. Writes the same `username` field
// setUsername does -- one row cannot carry two addresses without drifting --
// but answers with a status and a ladder of free alternatives instead of
// throwing, because a taken handle is a normal step in onboarding.
export const claimHandle = mutation({
  args: { handle: v.string() },
  returns: claimHandleValidator,
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "claimHandle", 10, MINUTE_MS);
    const handle = validateUsername(args.handle);
    const existing = await getProfileByUser(ctx, userId);

    // Check and claim in the same mutation: Convex serializes the two writes,
    // so a race ends with one "claimed" and one "taken", never a duplicate.
    const holder = await getProfileByUsername(ctx, handle);
    if (holder !== null && holder.userId !== userId) {
      // Suggestions come from the caller's own name, and only unheld rungs
      // qualify -- which also drops the handle they already own.
      const suggestions =
        existing?.name === undefined
          ? []
          : await freeCandidates(ctx, existing.name, HANDLE_SUGGESTIONS);
      return { status: "taken" as const, handle, suggestions };
    }

    const now = Date.now();
    if (existing === null) {
      await ctx.db.insert("profiles", {
        userId,
        username: handle,
        updatedAt: now,
      });
    } else if (existing.username !== handle) {
      await ctx.db.patch("profiles", existing._id, {
        username: handle,
        updatedAt: now,
      });
    }
    return { status: "claimed" as const, handle, suggestions: [] };
  },
});

// Deliberately unauthenticated: this backs the public web card that a scanned
// beacon opens. Every field it returns is one a stranger may see.
export const getByHandle = query({
  args: { handle: v.string() },
  returns: v.union(v.null(), publicCardValidator),
  handler: async (ctx, args) => {
    const handle = normalizeUsername(args.handle);
    if (!USERNAME_PATTERN.test(handle)) {
      return null;
    }
    const profile = await getProfileByUsername(ctx, handle);
    if (profile === null) {
      return null;
    }
    return await toPublicCard(ctx, profile);
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
