import {
  internalMutation,
  mutation,
  query,
  MutationCtx,
  QueryCtx,
} from "./_generated/server";
import { Infer, v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import { requireUser } from "./authz";
import { checkRateLimit } from "./rateLimit";
import { normalizeName, personSearchText } from "./nameSearch";
import { requireImageBlob } from "./imageBlobs";
import { deleteMemories } from "./memories";
import { endConnection } from "./connections";
import { ensureEvent, eventInputValidator, linkEventPerson } from "./events";
import {
  cityInputValidator,
  cityValidator,
  handleValidator,
  onboardingStateValidator,
  onboardingStepValidator,
  onboardingValidator,
  platformValidator,
  publicHandleValidator,
  toCityInput,
} from "./profileFields";
import { handleDisplayValue, handleIndexKeys, hasPhoneDigit } from "./handleKeys";
import { HANDLE_PATTERN, isReservedHandle } from "./handleNames";
import {
  CARD_LINE_MAX,
  CARD_NAME_MAX,
  CITY_PART_MAX,
  HANDLE_MAX,
  requireWithin,
} from "./fieldCaps";

const MINUTE_MS = 60_000;

const USERNAME_MAX_LENGTH = 24;
const USERNAME_HELP = "Use 3-24 lowercase letters, numbers, or underscores";

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
  // Always present, null when there is no photo. The client needs to tell "no
  // photo" from "not loaded yet", and an absent key cannot say which.
  photoUrl: v.union(v.null(), v.string()),
  city: v.optional(cityValidator),
  handles: v.optional(v.array(handleValidator)),
  primaryPlatform: v.optional(platformValidator),
  company: v.optional(v.string()),
  role: v.optional(v.string()),
  onboarding: v.optional(onboardingValidator),
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
  if (!HANDLE_PATTERN.test(username)) {
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

// Company and role: one card line each, so one budget each.
function cappedLine(label: string, article: string, raw: string): string {
  const value = requireText(label, raw);
  requireWithin(article, value, CARD_LINE_MAX);
  return value;
}

function withCityKey(city: CityInput) {
  const name = requireText("City", city.name);
  requireWithin("a city name", name, CITY_PART_MAX);
  // Admin area and country render beside the city, so they share its budget.
  if (city.admin !== undefined) {
    requireWithin("a state or region", city.admin, CITY_PART_MAX);
  }
  if (city.country !== undefined) {
    requireWithin("a country", city.country, CITY_PART_MAX);
  }
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
    // Same refusal as people.ts's validateContactHandles, for the same
    // reason: a digitless phone value folds to a plain lowercase string, and
    // two different unreadable entries would otherwise be able to collide.
    // platformValidator has no "whatsapp" literal, so "phone" is the only
    // case a card handle can hit this on.
    if (handle.platform === "phone" && !hasPhoneDigit(handle.value)) {
      throw new Error("A phone number needs at least one digit");
    }
    return {
      platform: handle.platform,
      // This mutation is the authority on how a handle is stored: the client
      // parses for live preview only. Folding here with the same rules
      // people.saveSharedProfile uses means the account you publish on your
      // card and the account someone saves off it share one identity key,
      // however either side typed it.
      value: cappedHandleValue(handle.value),
      verified: handle.verified,
      // Composio's proven id for the account (composio.ts's
      // storeVerifiedHandle), passed through rather than dropped -- this is
      // the one field on the card that survives a rename, and a fold that
      // silently stripped it would make identity's platformId-preferred
      // dedup never fire for anything shared off a Haven card.
      platformId: handle.platformId,
    };
  });
}

function cappedHandleValue(raw: string): string {
  const value = requireText("A handle", handleDisplayValue(raw));
  requireWithin("a handle", value, HANDLE_MAX);
  return value;
}

const HANDLE_SUFFIX_TRIES = 10;
const HANDLE_SUGGESTIONS = 3;

// Address ladder for a name: bare first name, then first_last, then a short
// numeric suffix. Underscore rather than hyphen because HANDLE_PATTERN --
// shared with the legacy setUsername path -- allows only a-z, 0-9 and "_".
function handleCandidates(name: string): string[] {
  const parts = normalizeName(name)
    .split(" ")
    .map((part) => part.replace(/[^a-z0-9]/g, ""))
    .filter((part) => part !== "");
  // A name with no Latin characters at all still deserves an address, so fall
  // back to a generic base instead of failing the claim. Not "haven": the
  // brand is reserved so nobody can pose as it, and a fallback nobody can
  // claim is not a fallback.
  const first = parts[0] ?? "star";
  const base = parts.length > 1 ? `${first}_${parts[parts.length - 1]}` : first;
  const ladder = [first, base];
  for (let n = 2; n < 2 + HANDLE_SUFFIX_TRIES; n++) {
    const suffix = String(n);
    ladder.push(base.slice(0, USERNAME_MAX_LENGTH - suffix.length) + suffix);
  }
  return [
    ...new Set(
      ladder.map((candidate) => candidate.slice(0, USERNAME_MAX_LENGTH)),
    ),
  ].filter((candidate) => HANDLE_PATTERN.test(candidate));
}

async function freeCandidates(
  ctx: MutationCtx,
  name: string,
  limit: number,
): Promise<string[]> {
  const free: string[] = [];
  for (const candidate of handleCandidates(name)) {
    if (isReservedHandle(candidate)) {
      continue;
    }
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

// Async only because of the photo. A storage id is not something a client can
// fetch, so the URL is resolved here the same way the public card and the
// people list already do it.
async function toMyCard(ctx: QueryCtx, profile: Doc<"profiles">) {
  return {
    _id: profile._id,
    _creationTime: profile._creationTime,
    username: profile.username,
    updatedAt: profile.updatedAt,
    name: profile.name,
    photoStorageId: profile.photoStorageId,
    photoUrl:
      profile.photoStorageId === undefined
        ? null
        : await ctx.storage.getUrl(profile.photoStorageId),
    city: profile.city,
    handles: profile.handles,
    primaryPlatform: profile.primaryPlatform,
    company: profile.company,
    role: profile.role,
    onboarding: profile.onboarding,
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

// One side's directory row for the other. Idempotent on the contact's user
// id, so a repeat connection in person reuses the row rather than twinning
// the human.
async function ensureMeetPerson(args: {
  ctx: MutationCtx;
  ownerUserId: string;
  contact: Doc<"profiles">;
  now: number;
}): Promise<Id<"people">> {
  const contactUsername = args.contact.username;
  const existing = await args.ctx.db
    .query("people")
    .withIndex("by_user_and_havenContactUserId", (q) =>
      q
        .eq("userId", args.ownerUserId)
        .eq("havenContactUserId", args.contact.userId),
    )
    .unique();
  if (existing !== null) {
    // A pair who disconnected and met again thaws the row they already have.
    // A second contact for the same human is the one thing this path exists
    // to prevent, and the card they carry has moved on since the freeze.
    if (existing.connectionEndedAt !== undefined) {
      await args.ctx.db.patch("people", existing._id, {
        ...snapshotPatch(existing, args.contact),
        connectionEndedAt: undefined,
      });
      await args.ctx.scheduler.runAfter(0, internal.people.embed, {
        personId: existing._id,
      });
    }
    return existing._id;
  }

  // Their own name if they have set one. The handle is the fallback, not the
  // default: a directory full of "@bob" is a directory nobody can read.
  const displayName = args.contact.name ?? `@${contactUsername}`;
  // A Haven username is a handle like any other, so the person gets one in
  // contactHandles and a matching index row. Without them a person met in
  // person is invisible to every handle lookup, and re-sharing their profile
  // later would create a second row for the same human.
  const havenHandle = { platform: "haven", value: contactUsername };
  const city = toCityInput(args.contact.city);
  // Snapshotted so the row is findable by keyword the moment it lands. The
  // live values still win on read (projectConnectedPerson) -- this copy only
  // feeds the search indexes, which cannot query another table, and
  // refreshSnapshotPage keeps it current afterwards.
  const snapshot = {
    name: displayName,
    company: args.contact.company,
    role: args.contact.role,
    city,
    handle: contactUsername,
    contactHandles: [havenHandle],
  };
  const personId = await args.ctx.db.insert("people", {
    userId: args.ownerUserId,
    name: displayName,
    // From the underlying name, not the decorated display form: the "@" on a
    // handle fallback is sugar, and normalizing it in would make searching
    // "bob" miss the person shown as "@bob".
    normalizedName: normalizeName(args.contact.name ?? contactUsername),
    // This insert bypasses addPerson, so it feeds the keyword index itself.
    searchText: personSearchText(snapshot),
    company: args.contact.company,
    companyKey:
      args.contact.company === undefined
        ? undefined
        : normalizeName(args.contact.company),
    role: args.contact.role,
    roleKey:
      args.contact.role === undefined
        ? undefined
        : normalizeName(args.contact.role),
    city,
    cityKey: city === undefined ? undefined : normalizeName(city.name),
    // No context, and so no memory row: a synthetic "met through Haven" line
    // would give every connection an identical, meaningless memory, and the
    // edge already records the provenance. The first memory of this person
    // should be one the user actually wrote.
    updatedAt: args.now,
    // The legacy scalars stay: the web meet UI reads them, and the index is
    // an addition rather than a replacement.
    platform: "Haven",
    handle: contactUsername,
    contactHandles: [havenHandle],
    havenContactUserId: args.contact.userId,
  });
  await args.ctx.db.insert("personHandles", {
    userId: args.ownerUserId,
    personId,
    ...handleIndexKeys(havenHandle),
  });
  await args.ctx.scheduler.runAfter(0, internal.people.embed, { personId });
  return personId;
}

// How many referencing rows one fan-out transaction refreshes. Smaller than
// PURGE_PAGE because each refreshed row also schedules an embed.
const SNAPSHOT_PAGE = 100;

// The card fields a connection's directory row snapshots. A photo or a
// handle edit changes nothing that lives on the other side's row, so it
// schedules no fan-out.
const SNAPSHOT_FIELDS = ["name", "company", "role", "city"] as const;

function sameCity(a: CityInput | undefined, b: CityInput | undefined): boolean {
  return (
    a?.name === b?.name && a?.admin === b?.admin && a?.country === b?.country
  );
}

// What one referencing row has to change to match the peer's current card.
//
// Mirrors projectConnectedPerson field for field, and that is the invariant:
// the snapshot only exists to feed the search indexes, which cannot read
// another table, so it has to hold exactly what the detail read renders or
// search and card disagree about the same person. A field the peer does not
// have is left alone for the same reason -- the read falls back to the
// snapshot there, so clearing it would hide something still on screen.
function snapshotPatch(
  person: Doc<"people">,
  profile: Doc<"profiles">,
): Partial<Doc<"people">> {
  const next: Partial<Doc<"people">> = {};
  if (profile.name !== undefined) {
    if (profile.name !== person.name) {
      next.name = profile.name;
      next.normalizedName = normalizeName(profile.name);
    }
  } else if (person.name === `@${person.handle}`) {
    // A peer with no card name has only the handle fallback, and the owner
    // may have relabelled the row since. The fallback refreshes only while
    // it is still the fallback: a name the owner typed is theirs to keep.
    const fallback = `@${profile.username}`;
    if (fallback !== person.name) {
      next.name = fallback;
      next.normalizedName = normalizeName(profile.username);
    }
  }
  if (profile.company !== undefined && profile.company !== person.company) {
    next.company = profile.company;
    next.companyKey = normalizeName(profile.company);
  }
  if (profile.role !== undefined && profile.role !== person.role) {
    next.role = profile.role;
    next.roleKey = normalizeName(profile.role);
  }
  const city = toCityInput(profile.city);
  if (city !== undefined && !sameCity(city, person.city)) {
    next.city = city;
    next.cityKey = normalizeName(city.name);
  }
  const searchText = personSearchText({ ...person, ...next });
  if (searchText !== person.searchText) {
    next.searchText = searchText;
  }
  return next;
}

// One page of the fan-out that keeps every connection's directory row current
// with the peer's card, rescheduling itself while more rows remain -- the
// same shape purgeOwnedRows uses, except a refresh does not remove the rows
// it visits, so progress needs a cursor rather than a shrinking head.
//
// updatedAt is deliberately not touched: the Directory pages
// most-recently-touched first, and somebody else editing their own card is
// not the owner touching this row.
async function refreshSnapshotPage(
  ctx: MutationCtx,
  profile: Doc<"profiles">,
  cursor: string | null,
): Promise<void> {
  const page = await ctx.db
    .query("people")
    .withIndex("by_havenContactUserId", (q) =>
      q.eq("havenContactUserId", profile.userId),
    )
    .paginate({ numItems: SNAPSHOT_PAGE, cursor });
  for (const person of page.page) {
    // A frozen row keeps naming the peer so a reconnection can thaw it, and
    // refreshing it would undo the freeze one field at a time.
    if (person.connectionEndedAt !== undefined) {
      continue;
    }
    const fields = snapshotPatch(person, profile);
    if (Object.keys(fields).length === 0) {
      continue;
    }
    await ctx.db.patch("people", person._id, fields);
    // The row's searchable text moved, so its vector has to move with it or
    // semantic search keeps answering with the card they used to have.
    await ctx.scheduler.runAfter(0, internal.people.embed, {
      personId: person._id,
    });
  }
  if (!page.isDone) {
    await ctx.scheduler.runAfter(
      0,
      internal.profiles.refreshConnectionSnapshots,
      { userId: profile.userId, cursor: page.continueCursor },
    );
  }
}

// The continuation of a fan-out that did not fit in one transaction. Reads
// the profile again rather than trusting the caller's copy: a card edited
// twice in a row must not finish its first fan-out with the older card.
export const refreshConnectionSnapshots = internalMutation({
  args: { userId: v.string(), cursor: v.union(v.string(), v.null()) },
  returns: v.null(),
  handler: async (ctx, args) => {
    const profile = await getProfileByUser(ctx, args.userId);
    if (profile === null) {
      return null;
    }
    await refreshSnapshotPage(ctx, profile, args.cursor);
    return null;
  },
});

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

// Where a profile photo is uploaded before it is attached.
//
// Its own function rather than a shared one with captures: the two are
// different spends with different limits, and a single URL minter would make
// a photo import and a screenshot capture compete for one budget.
//
// Rate limited because a URL is a write into storage. The orphan sweep
// reclaims blobs nobody references, but a sweep is a cleanup, not a cap.
export const generateUploadUrl = mutation({
  args: {},
  returns: v.string(),
  handler: async (ctx) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(
      ctx,
      userId,
      "profiles:generateUploadUrl",
      10,
      MINUTE_MS,
    );
    return await ctx.storage.generateUploadUrl();
  },
});

// Records what happened to one onboarding question.
//
// The client kept this on the device, which loses the answer on reinstall and
// says nothing on a second phone. The card cannot carry it either: a declined
// city and a city nobody has been asked for leave the same empty field. So it
// is its own record, and the device store becomes a cache of it.
export const recordOnboardingStep = mutation({
  args: {
    step: onboardingStepValidator,
    state: onboardingStateValidator,
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "recordOnboardingStep", 60, MINUTE_MS);
    // Name is the one required answer -- the card has nothing to show without
    // it, and the beacon address is minted from it -- so nothing offers to
    // skip it and a client that tries is refused rather than believed.
    if (args.step === "name" && args.state === "skipped") {
      throw new Error("The name question cannot be skipped");
    }
    const profile = await getProfileByUser(ctx, userId);
    if (profile === null) {
      throw new Error("Enter your name first");
    }

    const onboarding = { ...profile.onboarding, [args.step]: args.state };
    const decided = ONBOARDING_STEPS.every(
      (step) => onboarding[step] !== undefined,
    );
    // Stamped once, on the transition. This is when someone got through
    // onboarding, not when they last edited a field, so a later answer to an
    // already-decided question leaves it alone.
    if (decided && onboarding.completedAt === undefined) {
      onboarding.completedAt = Date.now();
    }

    await ctx.db.patch("profiles", profile._id, { onboarding });
    return null;
  },
});

const ONBOARDING_STEPS = ["name", "location", "contact"] as const;

// How many rows of one table a single purge transaction removes. Deliberately
// well under Convex's per-transaction ceiling: the purge reschedules itself
// while any table is still full, so the bound costs a few more transactions
// and buys an account that deletes however much the person accumulated.
const PURGE_PAGE = 200;

// Deletes the caller's account: the profile row first, so the address stops
// resolving the moment this returns, then everything they own.
//
// Idempotent on purpose. There is no row to "not find" -- a second tap, or a
// tap by someone who never finished onboarding, is the same request and gets
// the same answer, per the repo's creation convention read backwards.
//
// Other people's rows about the caller are not touched. A person someone else
// saved is their private note, and account deletion is not a right to reach
// into somebody else's directory.
export const deleteMyAccount = mutation({
  args: {},
  returns: v.null(),
  handler: async (ctx) => {
    const userId = await requireUser(ctx);
    const profile = await getProfileByUser(ctx, userId);
    if (profile !== null) {
      if (profile.photoStorageId !== undefined) {
        await ctx.storage.delete(profile.photoStorageId);
      }
      await ctx.db.delete("profiles", profile._id);
    }
    await purgeOwnedRows(ctx, userId);
    // Scheduled, not awaited: this mutation cannot reach the network, and
    // Composio has no idea a Convex account was just deleted -- left alone,
    // a connected account keeps its OAuth tokens alive there under this
    // userId forever. See deleteConnectedAccountsForUser's own comment for
    // why every failure it can hit is caught rather than surfaced: the
    // account is gone the moment this mutation returns, regardless of
    // whether Composio ever answers.
    await ctx.scheduler.runAfter(
      0,
      internal.composio.deleteConnectedAccountsForUser,
      { userId },
    );
    return null;
  },
});

// The continuation of a purge that did not fit in one transaction.
//
// Guarded on the profile row being absent: if the person signed back in and
// started a new card while this was queued, the rows it would delete are the
// new account's, and finishing the old purge would empty a directory nobody
// asked to empty.
export const purgeAccountData = internalMutation({
  args: { userId: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    if ((await getProfileByUser(ctx, args.userId)) !== null) {
      return null;
    }
    await purgeOwnedRows(ctx, args.userId);
    return null;
  },
});

// One page across every table the user owns rows in, rescheduling itself if
// any table still has more. Blobs go with their rows: a file nobody can reach
// is still a file we are storing about someone who asked to be forgotten.
async function purgeOwnedRows(ctx: MutationCtx, userId: string): Promise<void> {
  let more = false;

  const people = await ctx.db
    .query("people")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .take(PURGE_PAGE);
  for (const person of people) {
    if (person.screenshotId !== undefined) {
      await ctx.storage.delete(person.screenshotId);
    }
    if (person.photoStorageId !== undefined) {
      await ctx.storage.delete(person.photoStorageId);
    }
    const handles = await ctx.db
      .query("personHandles")
      .withIndex("by_person", (q) => q.eq("personId", person._id))
      .collect();
    for (const handle of handles) {
      await ctx.db.delete("personHandles", handle._id);
    }
    // Same cascade deletePerson does. Without it a deleted account leaves its
    // memory lines behind, still carrying its userId and still sitting in the
    // vector index: an account deletion that does not delete everything.
    await deleteMemories(ctx, person._id);
    await ctx.db.delete("people", person._id);
  }
  more ||= people.length === PURGE_PAGE;

  const captures = await ctx.db
    .query("captures")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .take(PURGE_PAGE);
  for (const capture of captures) {
    await ctx.storage.delete(capture.screenshotId);
    await ctx.db.delete("captures", capture._id);
  }
  more ||= captures.length === PURGE_PAGE;

  const eventLinks = await ctx.db
    .query("eventPeople")
    .withIndex("by_userId", (q) => q.eq("userId", userId))
    .take(PURGE_PAGE);
  for (const link of eventLinks) {
    await ctx.db.delete("eventPeople", link._id);
  }
  more ||= eventLinks.length === PURGE_PAGE;

  const events = await ctx.db
    .query("events")
    .withIndex("by_userId_and_startedAt", (q) => q.eq("userId", userId))
    .take(PURGE_PAGE);
  for (const event of events) {
    await ctx.db.delete("events", event._id);
  }
  more ||= events.length === PURGE_PAGE;

  // Contacts in other people's directories that referenced this account
  // collapse to a frozen snapshot they own, like a phone contact: the memory
  // of a person is the directory owner's, but the live canonical card belongs
  // to whoever is leaving and goes with them (mvp-design, deletion
  // semantics). Dropping only the reference leaves the snapshot readable.
  const referencing = await ctx.db
    .query("people")
    .withIndex("by_havenContactUserId", (q) =>
      q.eq("havenContactUserId", userId),
    )
    .take(PURGE_PAGE);
  for (const person of referencing) {
    await ctx.db.patch("people", person._id, {
      havenContactUserId: undefined,
      connectionEndedAt: Date.now(),
    });
  }
  more ||= referencing.length === PURGE_PAGE;

  // Both sides of a connection, and the shared note that hangs off it. A note
  // written together stops being reachable when one side leaves, so leaving
  // the row behind would keep the other person's half of a conversation
  // pointing at nothing.
  for (const side of ["A", "B"] as const) {
    const connections = await ctx.db
      .query("connections")
      .withIndex(
        side === "A" ? "by_userAId_and_personAId" : "by_userBId_and_personBId",
        (q) =>
          side === "A" ? q.eq("userAId", userId) : q.eq("userBId", userId),
      )
      .take(PURGE_PAGE);
    for (const connection of connections) {
      const notes = await ctx.db
        .query("sharedNotes")
        .withIndex("by_connectionId", (q) =>
          q.eq("connectionId", connection._id),
        )
        .collect();
      for (const note of notes) {
        await ctx.db.delete("sharedNotes", note._id);
      }
      await ctx.db.delete("connections", connection._id);
    }
    more ||= connections.length === PURGE_PAGE;
  }

  // Ephemeral by design and expiring anyway, but a presence row keyed to a
  // deleted account still names them in a room until it does.
  const presence = await ctx.db
    .query("loveAlarmPresence")
    .withIndex("by_userId_and_expiresAt", (q) => q.eq("userId", userId))
    .take(PURGE_PAGE);
  for (const row of presence) {
    await ctx.db.delete("loveAlarmPresence", row._id);
  }
  more ||= presence.length === PURGE_PAGE;

  // subscriptions rows are deliberately not purged, and this is the only
  // table that survives. What was charged to a card is the billing system's
  // record, not the account's: it answers refund and chargeback questions
  // long after the account is gone, and it is keyed to a Stripe customer
  // rather than describing the person. Deleting it would leave money moved
  // with nothing on our side saying why.

  // Preview admission belongs to the Clerk account, so it leaves with the
  // account too. Keeping it would silently re-admit a later session carrying
  // the same identity after the person asked Haven to forget them.
  const previewGrant = await ctx.db
    .query("previewAccess")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .unique();
  if (previewGrant !== null) {
    await ctx.db.delete("previewAccess", previewGrant._id);
  }

  // Last, because every delete above ran under a limiter that keys off this
  // table: clearing it first would let the purge lift the caller's own caps.
  const limits = await ctx.db
    .query("rateLimits")
    .withIndex("by_user_action", (q) => q.eq("userId", userId))
    .take(PURGE_PAGE);
  for (const limit of limits) {
    await ctx.db.delete("rateLimits", limit._id);
  }
  more ||= limits.length === PURGE_PAGE;

  if (more) {
    await ctx.scheduler.runAfter(0, internal.profiles.purgeAccountData, {
      userId,
    });
  }
}

// The caller's whole card. Onboarding resumes at the first unanswered question,
// and the client works that out from this, not from a local counter: a counter
// is lost on reinstall and lies after an edit on another device.
export const getMyCard = query({
  args: {},
  returns: v.union(v.null(), myCardValidator),
  handler: async (ctx) => {
    const userId = await requireUser(ctx);
    const profile = await getProfileByUser(ctx, userId);
    return profile === null ? null : await toMyCard(ctx, profile);
  },
});

export const setUsername = mutation({
  args: { username: v.string() },
  returns: myProfileValidator,
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "setUsername", 10, MINUTE_MS);
    const username = validateUsername(args.username);
    if (isReservedHandle(username)) {
      throw new Error(`"${username}" is not available`);
    }
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
      requireWithin("your name", name, CARD_NAME_MAX);
      fields.name = name;
    }
    if (args.photoStorageId !== undefined) {
      if (args.photoStorageId !== null) {
        await requireImageBlob(
          ctx,
          args.photoStorageId,
          "Please choose an image under 10 MB",
        );
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
        args.company === null
          ? undefined
          : cappedLine("Company", "a company", args.company);
    }
    if (args.role !== undefined) {
      fields.role =
        args.role === null ? undefined : cappedLine("Role", "a role", args.role);
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
      return await toMyCard(ctx, created);
    }

    await ctx.db.patch("profiles", existing._id, { ...fields, updatedAt: now });
    const updated = await ctx.db.get("profiles", existing._id);
    if (updated === null) {
      throw new Error("Could not save profile");
    }
    // Every connection holds a snapshot of this card so their search index has
    // something to match on, and a snapshot nobody refreshes is exactly the
    // stale contact Haven exists to abolish. The first page runs here, so the
    // common card edit is current the moment this returns; the rest is
    // scheduled. The insert branch above needs none: a profile that did not
    // exist a moment ago cannot be referenced.
    if (SNAPSHOT_FIELDS.some((field) => field in fields)) {
      await refreshSnapshotPage(ctx, updated, null);
    }
    return await toMyCard(ctx, updated);
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
    // A name the site needs for itself reads as taken rather than as an error.
    // It is unavailable, which is the same answer as a name someone else
    // holds, and it deserves the same way forward.
    if (isReservedHandle(handle) || (holder !== null && holder.userId !== userId)) {
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
    if (!HANDLE_PATTERN.test(handle)) {
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
    if (!HANDLE_PATTERN.test(username)) {
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

// Two Haven users become a mutual connection in one tap, with no request and
// accept dance: connecting in person is the consent (mvp-design). One edge,
// and a directory row on each side that references the other's live card
// rather than copying it.
//
// Sorted, not caller-ordered: one pair must produce exactly one row whichever
// side scans first, and sharedNotes resolves the edge with .unique(), so a
// second row would throw rather than merely duplicate.
function connectionPair(x: string, y: string) {
  return x < y
    ? { userAId: x, userBId: y, callerIsA: true }
    : { userAId: y, userBId: x, callerIsA: false };
}

export const connect = mutation({
  args: {
    username: v.string(),
    event: v.optional(eventInputValidator),
  },
  returns: v.object({
    // "already" when the pair was connected before, whichever side did it.
    status: v.union(v.literal("connected"), v.literal("already")),
    personId: v.id("people"),
    peerUsername: v.string(),
  }),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "connect", 20, MINUTE_MS);
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
      contact: peerProfile,
      now,
    });
    const peerPersonId = await ensureMeetPerson({
      ctx,
      ownerUserId: peerProfile.userId,
      contact: myProfile,
      now,
    });
    if (args.event !== undefined) {
      const { event } = await ensureEvent(ctx, userId, args.event);
      await linkEventPerson(ctx, userId, event._id, personId);
    }

    const pair = connectionPair(userId, peerProfile.userId);
    const [personAId, personBId] = pair.callerIsA
      ? [personId, peerPersonId]
      : [peerPersonId, personId];
    const existing = await ctx.db
      .query("connections")
      .withIndex("by_userAId_and_userBId", (q) =>
        q.eq("userAId", pair.userAId).eq("userBId", pair.userBId),
      )
      .unique();
    if (existing !== null) {
      // Self-heal a stale edge rather than leave it dangling: a person row
      // deleted and remade by a later connection would otherwise leave the
      // edge pointing at a row that no longer exists, and sharedNotes reads
      // it through those ids.
      if (
        existing.personAId !== personAId ||
        existing.personBId !== personBId
      ) {
        await ctx.db.patch("connections", existing._id, {
          personAId,
          personBId,
          updatedAt: now,
        });
      }
      return {
        status: "already" as const,
        personId,
        peerUsername: peerProfile.username,
      };
    }

    await ctx.db.insert("connections", {
      userAId: pair.userAId,
      userBId: pair.userBId,
      personAId,
      personBId,
      status: "connected",
      createdAt: now,
      updatedAt: now,
    });
    return {
      status: "connected" as const,
      personId,
      peerUsername: peerProfile.username,
    };
  },
});

// The way out of a connection. Until this existed the only exit was
// deletePerson, which threw away the owner's own notes and photo to end a
// relationship -- and connecting is one tap, so ending one should not cost
// the memory of the person.
//
// Both sides keep their contact as the frozen snapshot they own; what ends
// is the live reference and the note the two of them wrote together. It is
// mutual because the edge is: there is no half of a connection to keep.
export const disconnect = mutation({
  args: { personId: v.id("people") },
  returns: v.object({
    // "notConnected" when there was no connection to end, which is the same
    // answer a second tap deserves.
    status: v.union(v.literal("disconnected"), v.literal("notConnected")),
  }),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "disconnect", 20, MINUTE_MS);
    const person = await ctx.db.get("people", args.personId);
    if (person === null || person.userId !== userId) {
      throw new Error("Person not found");
    }
    const ended = await endConnection(ctx, userId, args.personId, Date.now());
    return {
      status: ended ? ("disconnected" as const) : ("notConnected" as const),
    };
  },
});
