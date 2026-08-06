import {
  action,
  internalAction,
  internalMutation,
  internalQuery,
  mutation,
  query,
  ActionCtx,
  MutationCtx,
  QueryCtx,
} from "./_generated/server";
import { Infer, v } from "convex/values";
import {
  paginationOptsValidator,
  paginationResultValidator,
} from "convex/server";
import { internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import { buildDossier, buildEmbedText } from "../src/lib";
import { askNetwork, embedText } from "./openaiClient";
import { requireUser } from "./authz";
import { checkRateLimit } from "./rateLimit";
import { normalizeName, personSearchText } from "./nameSearch";
import { cityInputValidator, toCityInput } from "./profileFields";
import { contactHandleValidator, handleSourceValidator } from "./peopleFields";
import {
  handleDisplayValue,
  handleIndexKeys,
  handleValueKey,
  hasPhoneDigit,
  isPhoneNumberPlatform,
} from "./handleKeys";
import { requireImageBlob } from "./imageBlobs";
import { deleteMemories, syncMemories } from "./memories";
import { endConnection } from "./connections";
import {
  CARD_LINE_MAX,
  CARD_NAME_MAX,
  CITY_PART_MAX,
  HANDLE_MAX,
  requireWithin,
} from "./fieldCaps";

// Bound every list read so the query stays scalable as the table grows.
const RESULT_LIMIT = 20;

// Semantic matches below this cosine similarity read as noise, not memory.
// Tuned once against person-level vectors; single memory lines score on a
// different distribution, so this is due a recalibration against the wave B
// evaluation set rather than by feel.
const MIN_SEMANTIC_SCORE = 0.3;

// How many people one semantic search returns.
const SEMANTIC_RESULT_LIMIT = 8;

// Memory candidates pulled before aggregating per person. Wider than the
// result limit because many rows can belong to one person.
const MEMORY_CANDIDATE_LIMIT = 64;

const MINUTE_MS = 60_000;
const DAY_MS = 24 * 60 * MINUTE_MS;

// Keeps a single wildly long paste from bloating a document or dominating
// its own embedding.
const MAX_CONTEXT_LENGTH = 4000;
const CONTEXT_TOO_LONG_ERROR =
  "Context is too long -- keep it under 4000 characters";

// Same wording as the profile photo path: from the user's seat both are
// "pick a photo of this person".
const PHOTO_ERROR = "Please choose an image under 10 MB";

// The embeddings request has its own size ceiling; slicing here means an
// over-long stored context can never fail the whole embed call.
const MAX_EMBED_INPUT_LENGTH = 8000;

// Batch size for the maintenance mutations below, kept well under Convex's
// per-transaction document limits.
const BACKFILL_BATCH_SIZE = 500;

// Backoff schedule for the embed action: index 0 is the delay before retry
// attempt 1, index 1 before attempt 2. After that we give up.
const EMBED_RETRY_DELAYS_MS = [30_000, 5 * 60_000];

// Whether this row is a Haven connection, and which one.
//
// "connected": the peer's card merges into this row on the detail read, the
// shared note is reachable, and profiles.disconnect can end it.
// "ended": the row began as a connection and no longer references a live
// card -- the peer deleted their account, or one side disconnected. What is
// left is the snapshot the owner keeps, like a phone contact.
// null: an ordinary contact the owner saved themselves.
const connectionValidator = v.object({
  state: v.union(v.literal("connected"), v.literal("ended")),
  peerUsername: v.string(),
});

// What the client is ever allowed to see for a person. Never embedding,
// embeddedText, or userId -- those stay server-side.
const personValidator = v.object({
  _id: v.id("people"),
  _creationTime: v.number(),
  name: v.string(),
  link: v.optional(v.string()),
  context: v.optional(v.string()),
  platform: v.optional(v.string()),
  handle: v.optional(v.string()),
  headline: v.optional(v.string()),
  bio: v.optional(v.string()),
  screenshotId: v.optional(v.id("_storage")),
  city: v.optional(cityInputValidator),
  company: v.optional(v.string()),
  role: v.optional(v.string()),
  contactHandles: v.optional(v.array(contactHandleValidator)),
  preferredPlatform: v.optional(v.string()),
  // Resolved server-side: clients get a usable signed url, never a raw
  // storage id they cannot render.
  photoUrl: v.union(v.null(), v.string()),
  // Whether this row is somebody's live card or the owner's own notes, which
  // is what a client needs before it decides what is editable. The peer's
  // havenContactUserId stays server-side: it is their Clerk identity key,
  // and no client has a reason to read it -- the same rule myCardValidator
  // applies to the caller's own.
  connection: v.union(v.null(), connectionValidator),
  updatedAt: v.number(),
});

// Connection state read off the row alone, with no profile lookup: a
// directory page renders one of these per row, and a lookup each would turn
// a list read into a read per person.
function snapshotConnection(person: Doc<"people">) {
  // ensureMeetPerson is the only writer of havenContactUserId and always
  // writes the peer's username beside it, so a row with no handle names
  // nobody and is not renderable as a connection.
  const peerUsername = person.handle;
  if (peerUsername === undefined) {
    return null;
  }
  // Ended wins over the reference: a disconnect keeps havenContactUserId so
  // that reconnecting later finds this row instead of making a second
  // contact for the same human, and the row is frozen until it does.
  if (person.connectionEndedAt !== undefined) {
    return { state: "ended" as const, peerUsername };
  }
  if (person.havenContactUserId !== undefined) {
    return { state: "connected" as const, peerUsername };
  }
  return null;
}

async function projectPerson(ctx: QueryCtx, person: Doc<"people">) {
  return {
    _id: person._id,
    _creationTime: person._creationTime,
    name: person.name,
    link: person.link,
    context: person.context,
    platform: person.platform,
    handle: person.handle,
    headline: person.headline,
    bio: person.bio,
    screenshotId: person.screenshotId,
    city: person.city,
    company: person.company,
    role: person.role,
    contactHandles: person.contactHandles,
    preferredPlatform: person.preferredPlatform,
    photoUrl:
      person.photoStorageId === undefined
        ? null
        : await ctx.storage.getUrl(person.photoStorageId),
    connection: snapshotConnection(person),
    updatedAt: person.updatedAt,
  };
}

type CityInput = Infer<typeof cityInputValidator>;

// Validators for the structured attributes shared by addPerson and editPerson.
const structuredAttributeArgs = {
  city: v.optional(cityInputValidator),
  company: v.optional(v.string()),
  role: v.optional(v.string()),
};

// Display value plus derived accent-folded key, so the Phase 3 chip filters
// can equality-match regardless of accents or casing while the UI keeps what
// the user typed. A key is never written without its display value.
function structuredAttributeFields(args: {
  city?: CityInput;
  company?: string;
  role?: string;
}) {
  const fields: {
    city?: CityInput;
    cityKey?: string;
    company?: string;
    companyKey?: string;
    role?: string;
    roleKey?: string;
  } = {};
  if (args.company !== undefined) {
    const company = args.company.trim();
    if (company === "") {
      throw new Error("Company cannot be blank");
    }
    requireWithin("a company", company, CARD_LINE_MAX);
    fields.company = company;
    fields.companyKey = normalizeName(company);
  }
  if (args.role !== undefined) {
    const role = args.role.trim();
    if (role === "") {
      throw new Error("Role cannot be blank");
    }
    requireWithin("a role", role, CARD_LINE_MAX);
    fields.role = role;
    fields.roleKey = normalizeName(role);
  }
  if (args.city !== undefined) {
    const name = args.city.name.trim();
    if (name === "") {
      throw new Error("City cannot be blank");
    }
    requireWithin("a city name", name, CITY_PART_MAX);
    // Admin area and country render beside the city, so they share its budget.
    if (args.city.admin !== undefined) {
      requireWithin("a state or region", args.city.admin, CITY_PART_MAX);
    }
    if (args.city.country !== undefined) {
      requireWithin("a country", args.city.country, CITY_PART_MAX);
    }
    fields.city = { ...args.city, name };
    fields.cityKey = normalizeName(name);
  }
  return fields;
}

export type ContactHandleInput = Infer<typeof contactHandleValidator>;

export const MAX_CONTACT_HANDLES = 8;

// One handle per normalized platform keeps the preferredPlatform pointer
// unambiguous -- same reasoning as profiles.primaryPlatform, except the
// platform itself is free-form text here rather than a fixed union.
function validateContactHandles(
  handles: ContactHandleInput[],
): ContactHandleInput[] {
  if (handles.length > MAX_CONTACT_HANDLES) {
    throw new Error(`Keep at most ${MAX_CONTACT_HANDLES} contact handles`);
  }
  const seen = new Set<string>();
  return handles.map((handle) => {
    const platform = handle.platform.trim().toLowerCase();
    if (platform === "") {
      throw new Error("A platform cannot be blank");
    }
    const value = handle.value.trim();
    if (value === "") {
      throw new Error("A handle cannot be blank");
    }
    // A digitless phone/whatsapp value ("unknown", "ask mai", an OCR miss)
    // folds through handleValueKey's own lowercase fallback -- two different
    // unreadable values from two different strangers would otherwise collide
    // on the same personHandles row (see handleKeys.ts's hasPhoneDigit).
    // Every write path a person is actually present for goes through this
    // function (addPerson, editPerson, saveSharedProfile all reach it), so
    // the refusal belongs here rather than repeated at each caller.
    if (isPhoneNumberPlatform(platform) && !hasPhoneDigit(value)) {
      throw new Error("A phone number needs at least one digit");
    }
    if (seen.has(platform)) {
      throw new Error("Keep one handle per platform");
    }
    seen.add(platform);
    // source, platformId and addedAt pass through untouched: this is the
    // fold every write path shares, capture pipelines included, and a fold
    // that dropped provenance would make every other piece of it a no-op --
    // the value would still dedup correctly, but nothing would ever again
    // know a handle had been proven, or what its stable id was.
    return {
      platform,
      value,
      source: handle.source,
      platformId: handle.platformId,
      addedAt: handle.addedAt,
    };
  });
}

// The interactive paths' handle validation: the same folding, plus the cap,
// plus a source. Deliberately not folded into validateContactHandles, which
// the capture paths also use -- those run without the user present, so they
// stay lenient rather than failing a queued share nobody can shorten, and
// they stamp their own source (captures.ts) rather than defaulting to
// "typed", which would be a lie about who entered the handle.
function validateOwnedHandles(
  handles: ContactHandleInput[],
): ContactHandleInput[] {
  return validateContactHandles(handles).map((handle) => {
    requireWithin("a handle", handle.value, HANDLE_MAX);
    // A hand-filled form is the one source this file is certain of when the
    // caller does not say otherwise -- addPerson and editPerson have no
    // other way a handle could have arrived.
    return { ...handle, source: handle.source ?? "typed" };
  });
}

export async function insertPersonHandles(
  ctx: MutationCtx,
  userId: string,
  personId: Id<"people">,
  handles: ContactHandleInput[],
): Promise<void> {
  for (const handle of handles) {
    await ctx.db.insert("personHandles", {
      userId,
      personId,
      ...handleIndexKeys(handle),
    });
  }
}

// Bounded by construction: one row per contactHandles entry, and that array
// is capped at MAX_CONTACT_HANDLES on every write path.
export async function deletePersonHandles(
  ctx: MutationCtx,
  personId: Id<"people">,
): Promise<void> {
  const rows = await ctx.db
    .query("personHandles")
    .withIndex("by_person", (q) => q.eq("personId", personId))
    .take(MAX_CONTACT_HANDLES);
  for (const row of rows) {
    await ctx.db.delete("personHandles", row._id);
  }
}

// A scan bound, not an expected count: one (userId, platform, valueKey)
// should own at most one row by construction. Shared with
// reportDuplicateHandleOwners below, which names the same cap for the same
// reason -- a handle owned by more people than this is already a five-alarm
// finding.
const MAX_HANDLE_OWNERS = 64;

// Temporary safety net while backfillPhoneHandleKeys moves legacy phone and
// WhatsApp index rows from trim+lowercase keys to the current phone-aware
// fold. An index miss must not mean "safe to create" during that window: the
// legacy index row still has the original valueKey, so a bounded scan of the
// user's small handle rows can prove the owner without guessing a country.
// The cap is defensive, and failing closed at it is safer than minting a
// duplicate identity.
const MAX_PHONE_MIGRATION_FALLBACK_HANDLES = 4096;

async function findPhoneOwnerDuringKeyMigration(
  ctx: MutationCtx,
  userId: string,
  platform: string,
  valueKey: string,
): Promise<Doc<"people"> | null> {
  if (!isPhoneNumberPlatform(platform)) {
    return null;
  }
  const rows = await ctx.db
    .query("personHandles")
    .withIndex("by_user_and_platform_and_valueKey", (q) =>
      q.eq("userId", userId).eq("platform", platform),
    )
    .take(MAX_PHONE_MIGRATION_FALLBACK_HANDLES + 1);
  if (rows.length > MAX_PHONE_MIGRATION_FALLBACK_HANDLES) {
    throw new Error(
      "Phone identity migration is incomplete. Finish the phone handle backfill before saving this number.",
    );
  }
  const candidates = rows.filter(
    (row) => handleValueKey(row.valueKey, platform) === valueKey,
  );
  return await oldestLiveOwner(ctx, userId, candidates, platform);
}

// Resolves a set of rows that already name one identity (a (userId,
// platform, valueKey) or (userId, platform, platformId) match) to its oldest
// still-live owner. Shared by both lookups in findHandleOwner below, so "two
// rows for one identity" is handled identically -- logged and resolved to
// the oldest -- regardless of which key found them.
//
// Tiebreaks on the owner PERSON's own _creationTime, not the personHandles
// row's: a row is rewritten (deletePersonHandles + insertPersonHandles) on
// every rename or contactHandles edit, so its _creationTime resets to
// "whenever that edit happened" and says nothing about which person has
// actually been known longer. The person doc's _creationTime is the one
// timestamp here nothing ever resets.
async function oldestLiveOwner(
  ctx: MutationCtx,
  userId: string,
  rows: Doc<"personHandles">[],
  platform: string,
): Promise<Doc<"people"> | null> {
  if (rows.length > 1) {
    // platform + row ids only -- never the valueKey or platformId a caller
    // passed in, which on most platforms is the personal handle itself.
    console.error(
      `findHandleOwner: ${rows.length} rows for platform=${platform}, ` +
        `attaching to the oldest (rows=${rows.map((row) => row._id).join(",")})`,
    );
  }
  const owners: Doc<"people">[] = [];
  for (const row of rows) {
    // The index this file's two callers query is already scoped to
    // q.eq("userId", userId), so this can only fire on a row whose OWN
    // userId happens to still match but whose personId now points at
    // somebody else's person (a corrupt pointer, not a stale index) --
    // caught below by the owner.userId check instead, since that is the
    // shape this can actually arrive in. Kept here too as the same
    // redacted-log belt, in case a future caller ever hands this rows from
    // an unscoped read.
    if (row.userId !== userId) {
      console.error(
        `findHandleOwner: cross-tenant row for platform=${platform} (row=${row._id}), skipping`,
      );
      continue;
    }
    const owner = await ctx.db.get("people", row.personId);
    if (owner === null) {
      // Self-heal a row orphaned by a write that bypassed deletePerson,
      // rather than let it shadow -- or, within a duplicate group, outrank
      // -- a real owner.
      await ctx.db.delete("personHandles", row._id);
      continue;
    }
    if (owner.userId !== userId) {
      // A personId pointer that now names a different tenant's person --
      // never leaked into the result, whatever wrote it that way.
      console.error(
        `findHandleOwner: row for platform=${platform} (row=${row._id}) points at a different tenant's person, skipping`,
      );
      continue;
    }
    owners.push(owner);
  }
  if (owners.length === 0) {
    return null;
  }
  owners.sort((a, b) => a._creationTime - b._creationTime);
  return owners[0];
}

// The current owner of one handle, tolerant of corruption a throwing
// .unique() would jam on: addPerson and editPerson gate new writes so two
// rows should never appear going forward, but rows written before that gate
// -- or by a path this file does not cover, like the capture pipeline --
// can still leave two. Rather than surface that as an error the caller
// cannot resolve, the oldest row wins deterministically and the corruption
// is logged; reportDuplicateHandleOwners stays the reconciliation surface
// for a human to actually merge the twins.
//
// platformId, when the incoming handle carries one, is tried first: it is a
// platform's own stable id for the account, so it still finds the right
// person after a username rename, which valueKey -- folded from the
// username itself -- cannot. A stored row with no platformId simply never
// matches the platformId lookup (Convex index equality does not treat
// undefined as a wildcard), so this can never falsely match an old,
// unproven row against a new proven one; valueKey stays the fallback for
// exactly that case.
export async function findHandleOwner(
  ctx: MutationCtx,
  userId: string,
  platform: string,
  valueKey: string,
  platformId?: string,
): Promise<Doc<"people"> | null> {
  if (platformId !== undefined) {
    const rows = await ctx.db
      .query("personHandles")
      .withIndex("by_user_and_platform_and_platformId", (q) =>
        q.eq("userId", userId).eq("platform", platform).eq("platformId", platformId),
      )
      .take(MAX_HANDLE_OWNERS);
    const owner = await oldestLiveOwner(ctx, userId, rows, platform);
    if (owner !== null) {
      return owner;
    }
  }
  const rows = await ctx.db
    .query("personHandles")
    .withIndex("by_user_and_platform_and_valueKey", (q) =>
      q.eq("userId", userId).eq("platform", platform).eq("valueKey", valueKey),
    )
    .take(MAX_HANDLE_OWNERS);
  const owner = await oldestLiveOwner(ctx, userId, rows, platform);
  if (owner !== null) {
    return owner;
  }
  return await findPhoneOwnerDuringKeyMigration(ctx, userId, platform, valueKey);
}

// What changes on an owner's existing contactHandles array when a handle
// that findHandleOwner already resolved to this owner needs to be written
// there. Three outcomes: nothing (the owner already holds this exact
// account -- same platform, same valueKey), a rename in place (the owner
// has an entry for this platform but a different valueKey -- reached either
// through a stable platformId or after the person explicitly picked this
// owner for a rename without one, as LinkedIn requires), or a genuinely new
// platform for this owner, appended if there is room under the cap.
//
// addedAt is preserved on a rename (the account has been known since the
// original addedAt; only its name changed) and stamped fresh only when a
// platform is actually new to this owner -- "on newly stored handles only"
// from the identity brief. source and platformId on the incoming handle are
// stored as given; the caller decides those.
export type MergeHandleResult =
  | {
      status: "merged";
      handles: ContactHandleInput[];
      changed: boolean;
      handleDropped: boolean;
    }
  // An id match (this call was reached because findHandleOwner matched
  // `owner` by platformId) and a value match disagree about who this
  // account is: `owner` holds the id, but somebody else already owns the
  // incoming username outright. Zero-guess doctrine -- refuse rather than
  // pick a winner by overwriting the other person's handle onto this one.
  | { status: "refused"; conflictingOwnerId: Id<"people"> };

export async function mergeHandleIntoOwner(
  ctx: MutationCtx,
  userId: string,
  owner: Doc<"people">,
  existing: ContactHandleInput[],
  incoming: ContactHandleInput,
): Promise<MergeHandleResult> {
  const incomingKeys = handleIndexKeys(incoming);
  const index = existing.findIndex(
    (handle) => handleIndexKeys(handle).platform === incomingKeys.platform,
  );
  if (index !== -1) {
    const current = existing[index];
    if (handleIndexKeys(current).valueKey === incomingKeys.valueKey) {
      // Equal value does NOT mean equal account when both sides carry an id
      // and the ids disagree: username reassignment. The stored handle
      // (found by value, since findHandleOwner had no incoming.platformId
      // to match yet) belongs to whoever this platform's account was when
      // it was last proven -- if that account has since renamed away and a
      // different one claimed the same username, the value alone reads as
      // "the same person" while the ids prove otherwise. Refused rather
      // than silently attaching a stranger's note to `owner` -- the exact
      // wrong-person failure the id-preferred lookup exists to prevent.
      if (
        current.platformId !== undefined &&
        incoming.platformId !== undefined &&
        current.platformId !== incoming.platformId
      ) {
        return { status: "refused", conflictingOwnerId: owner._id };
      }
      // Equal value, but this submission may know something the stored
      // handle does not: a platformId resolved after the fact (Composio's
      // own-card lookup, a re-share that happened to carry one this time).
      // Enriching it in place is what the rest of rename-proofing depends
      // on -- without it, this handle can never become id-findable, and a
      // genuine rename later (a different valueKey, same id) has nothing to
      // match by id and mints a twin instead of updating this person.
      // addedAt and source both stay: this is enrichment, not a fresh claim.
      if (current.platformId === undefined && incoming.platformId !== undefined) {
        const next = [...existing];
        next[index] = { ...current, platformId: incoming.platformId };
        return { status: "merged", handles: next, changed: true, handleDropped: false };
      }
      return { status: "merged", handles: existing, changed: false, handleDropped: false };
    }
    // Before renaming this owner's entry in place: is the NEW valueKey
    // already somebody else's account? Asked with no platformId -- a
    // platformId lookup would just find `owner` again (or whichever person
    // it names), and the question here is specifically who the username
    // itself currently belongs to.
    const valueOwner = await findHandleOwner(
      ctx,
      userId,
      incomingKeys.platform,
      incomingKeys.valueKey,
    );
    if (valueOwner !== null && valueOwner._id !== owner._id) {
      return { status: "refused", conflictingOwnerId: valueOwner._id };
    }
    const next = [...existing];
    next[index] = { ...incoming, addedAt: current.addedAt };
    return { status: "merged", handles: next, changed: true, handleDropped: false };
  }
  if (existing.length >= MAX_CONTACT_HANDLES) {
    // The cap is invisible to whoever triggered this merge; stranding
    // everything else behind it (the note, a rename already resolved above)
    // would be worse than learning one fewer platform, so the merge still
    // lands and only this one handle is dropped -- surfaced to the caller
    // as handleDropped rather than silently lost.
    return { status: "merged", handles: existing, changed: false, handleDropped: true };
  }
  return {
    status: "merged",
    handles: [...existing, { ...incoming, addedAt: incoming.addedAt ?? Date.now() }],
    changed: true,
    handleDropped: false,
  };
}

// Stamps addedAt on a handle being written wholesale (a brand new person, or
// editPerson's whole-array replacement), preserving the timestamp of a
// platform+value pair that was already there rather than resetting it to
// now on every resubmission. previous is the person's own contactHandles
// before this write (empty for a person who does not exist yet); an
// explicit addedAt the caller already sent is trusted as-is.
export function withAddedAt(
  previous: ContactHandleInput[],
  handle: ContactHandleInput,
): ContactHandleInput {
  if (handle.addedAt !== undefined) {
    return handle;
  }
  const keys = handleIndexKeys(handle);
  const priorMatch = previous.find((existing) => {
    const existingKeys = handleIndexKeys(existing);
    return (
      existingKeys.platform === keys.platform &&
      existingKeys.valueKey === keys.valueKey
    );
  });
  return { ...handle, addedAt: priorMatch?.addedAt ?? Date.now() };
}

// A re-share must never discard what the user typed, so a new note joins the
// person's context instead of replacing it. Clamped rather than refused at
// the cap: the drain replays a queued note long after the sheet closed, so
// an overflow cannot ask the user and must not strand the capture. The
// caller is told when the cap cut the note, so a drain never mistakes a
// clipped save for a complete one.
export function appendContext(
  existing: string | undefined,
  note: string | undefined,
): { context: string | undefined; noteTruncated: boolean } {
  if (note === undefined) {
    return { context: existing, noteTruncated: false };
  }
  // At-least-once replay -- a queued capture retried after a dropped
  // response, a conflict retried by the client -- must not double the same
  // note into the context every time the same write lands twice. Matched
  // against whole stored lines (context is "\n"-joined notes), trimmed-exact
  // -- a plain substring check would read a genuinely new, shorter note
  // ("Acme") as a replay of an unrelated longer one that happens to contain
  // it ("Met at Acme"), and silently drop it.
  if (
    existing !== undefined &&
    note !== "" &&
    existing.split("\n").some((line) => line.trim() === note.trim())
  ) {
    return { context: existing, noteTruncated: false };
  }
  const next =
    existing === undefined || existing === "" ? note : `${existing}\n${note}`;
  const context = next.slice(0, MAX_CONTEXT_LENGTH);
  return { context, noteTruncated: context.length < next.length };
}

// The shared URL is the only pointer back to the profile -- a LinkedIn slug
// cannot be rebuilt into one -- so a person without a link keeps it. An
// existing link is overwritten only when the same write also proves that a
// same-platform handle was renamed; otherwise the user-chosen link wins.
function linkBackfill(
  person: Doc<"people">,
  profileUrl: string,
  replacingSamePlatformHandle = false,
): { link?: string } {
  if (
    profileUrl === "" ||
    (!replacingSamePlatformHandle && person.link !== undefined && person.link !== "")
  ) {
    return {};
  }
  return { link: profileUrl };
}

// The preferred platform must point at a handle that exists once the write
// lands, so callers pass the handle list the row will actually hold.
function validatePreferredPlatform(
  raw: string,
  handles: ContactHandleInput[],
): string {
  const preferred = raw.trim().toLowerCase();
  if (!handles.some((handle) => handle.platform === preferred)) {
    throw new Error("Choose a preferred platform you have a handle for");
  }
  return preferred;
}

// Merges a set of handles and a note onto a person addPerson has already
// decided is the right target -- either the one owner its own handle check
// found, or the one an attachToPersonId arg named directly. Shared so both
// callers report noteTruncated/handleDropped the same way.
async function attachToExistingPerson(
  ctx: MutationCtx,
  userId: string,
  owner: Doc<"people">,
  contactHandles: ContactHandleInput[],
  note: string,
): Promise<
  | {
      status: "attached" | "already";
      personId: Id<"people">;
      noteTruncated: boolean;
      handleDropped: boolean;
    }
  | { status: "conflict"; personIds: Id<"people">[] }
> {
  let nextHandles = owner.contactHandles ?? [];
  let handlesChanged = false;
  let handleDropped = false;
  for (const handle of contactHandles) {
    const merged = await mergeHandleIntoOwner(ctx, userId, owner, nextHandles, handle);
    if (merged.status === "refused") {
      // Zero-guess: nothing about this attach is written -- not this
      // handle, not the note, not any handle already merged earlier in this
      // same loop -- so a partial write can never mask the conflict the
      // caller still has to resolve.
      return {
        status: "conflict" as const,
        personIds: [owner._id, merged.conflictingOwnerId],
      };
    }
    nextHandles = merged.handles;
    if (merged.changed) handlesChanged = true;
    if (merged.handleDropped) handleDropped = true;
  }

  const fields: Partial<Doc<"people">> = {};
  const { context, noteTruncated } = appendContext(owner.context, note);
  if (context !== owner.context) {
    fields.context = context;
  }
  if (handlesChanged) {
    fields.contactHandles = nextHandles;
  }

  if (Object.keys(fields).length === 0) {
    return { status: "already", personId: owner._id, noteTruncated, handleDropped };
  }

  const now = Date.now();
  await ctx.db.patch("people", owner._id, {
    ...fields,
    searchText: personSearchText({ ...owner, ...fields }),
    updatedAt: now,
  });
  if (handlesChanged) {
    // A rename replaces one platform's row in place; a full rewrite is
    // simpler and, capped at 8, no more expensive than diffing which
    // platform actually changed.
    await deletePersonHandles(ctx, owner._id);
    await insertPersonHandles(ctx, userId, owner._id, nextHandles);
  }
  await syncMemories(ctx, {
    userId,
    personId: owner._id,
    context: fields.context,
    createdAt: now,
  });
  await ctx.scheduler.runAfter(0, internal.people.embed, { personId: owner._id });
  return { status: "attached", personId: owner._id, noteTruncated, handleDropped };
}

// noteTruncated and handleDropped mirror saveSharedProfile's outcome shape:
// a merge can silently clamp the note at the context cap or drop a handle
// past the 8-handle cap, and a caller that never learns either would report
// a complete save that was not one.
const addPersonAttachedFields = {
  personId: v.id("people"),
  noteTruncated: v.boolean(),
  handleDropped: v.boolean(),
};
const addPersonReturns = v.union(
  v.object({ status: v.literal("created"), personId: v.id("people") }),
  v.object({ status: v.literal("attached"), ...addPersonAttachedFields }),
  v.object({ status: v.literal("already"), ...addPersonAttachedFields }),
  v.object({
    status: v.literal("conflict"),
    personIds: v.array(v.id("people")),
  }),
);

// What both addPerson (the legacy, bare-id contract) and addPersonWithOutcome
// (the current one) actually do -- one dedup/attach/create implementation,
// two public shapes around it, so the identity behavior in here can never
// drift between which mutation name a given client happens to call.
type AddPersonArgs = {
  name: string;
  context?: string;
  contactHandles?: ContactHandleInput[];
  preferredPlatform?: string;
  photoStorageId?: Id<"_storage">;
  // Set when the caller already answered "same person?" -- from a SearchAdd
  // suggestion, e.g. -- so this save should not go looking for an owner
  // itself, it should land on the one the user already picked. Absent on
  // the legacy addPerson's own args: no client that only knows the old
  // bare-id contract has ever been able to send this.
  attachToPersonId?: Id<"people">;
  city?: CityInput;
  company?: string;
  role?: string;
};

async function addPersonCore(
  ctx: MutationCtx,
  args: AddPersonArgs,
): Promise<Infer<typeof addPersonReturns>> {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "addPerson", 30, MINUTE_MS);
    const name = args.name.trim();
    if (name === "") {
      throw new Error("Name is required");
    }
    requireWithin("a name", name, CARD_NAME_MAX);
    // Identity and a story are what make a manual add searchable and
    // referenceable later, so a handle and a note are required here; the
    // capture paths stay lenient because they run without the user present.
    const contactHandles = validateOwnedHandles(args.contactHandles ?? []);
    if (contactHandles.length === 0) {
      throw new Error("A contact handle is required");
    }
    if (args.context === undefined || args.context.trim() === "") {
      throw new Error("A note is required");
    }
    if (args.context.length > MAX_CONTEXT_LENGTH) {
      throw new Error(CONTEXT_TOO_LONG_ERROR);
    }
    if (args.photoStorageId !== undefined) {
      await requireImageBlob(ctx, args.photoStorageId, PHOTO_ERROR);
    }
    const preferredPlatform =
      args.preferredPlatform === undefined
        ? undefined
        : validatePreferredPlatform(args.preferredPlatform, contactHandles);

    // Identity beats a second trip through this form: every submitted handle
    // is checked against who already owns it before anything is written, the
    // same idempotent-creation rule saveSharedProfile already follows.
    // platformId-first: two forms of the same proven account (a rename)
    // still resolve to one owner.
    const ownersByHandle = await Promise.all(
      contactHandles.map(async (handle) => {
        const keys = handleIndexKeys(handle);
        return await findHandleOwner(
          ctx,
          userId,
          keys.platform,
          keys.valueKey,
          handle.platformId,
        );
      }),
    );
    const distinctOwners = [
      ...new Map(
        ownersByHandle
          .filter((owner): owner is Doc<"people"> => owner !== null)
          .map((owner) => [owner._id, owner] as const),
      ).values(),
    ];

    if (args.attachToPersonId !== undefined) {
      // The handle check still runs first (above): a handle already proven
      // to belong to someone else is not overridden by a client's "same
      // person?" guess, however confident. Only a handle with no owner, or
      // one whose only owner is the very person being attached to, may
      // proceed past this point.
      const conflicting = distinctOwners.filter(
        (owner) => owner._id !== args.attachToPersonId,
      );
      if (conflicting.length > 0) {
        return {
          status: "conflict" as const,
          personIds: conflicting.map((owner) => owner._id),
        };
      }
      const target = await ctx.db.get("people", args.attachToPersonId);
      if (target === null || target.userId !== userId) {
        throw new Error("Person not found");
      }
      const outcome = await attachToExistingPerson(
        ctx,
        userId,
        target,
        contactHandles,
        args.context,
      );
      if (outcome.status === "conflict") {
        return outcome;
      }
      return {
        status: outcome.status,
        personId: outcome.personId,
        noteTruncated: outcome.noteTruncated,
        handleDropped: outcome.handleDropped,
      };
    }

    if (distinctOwners.length > 1) {
      // Two submitted handles, two different existing owners: this is not
      // one person to attach to, and there is no honest way to guess which
      // owner is right. Nothing is written; the caller decides.
      return {
        status: "conflict" as const,
        personIds: distinctOwners.map((owner) => owner._id),
      };
    }

    if (distinctOwners.length === 1) {
      const outcome = await attachToExistingPerson(
        ctx,
        userId,
        distinctOwners[0],
        contactHandles,
        args.context,
      );
      if (outcome.status === "conflict") {
        return outcome;
      }
      return {
        status: outcome.status,
        personId: outcome.personId,
        noteTruncated: outcome.noteTruncated,
        handleDropped: outcome.handleDropped,
      };
    }

    // A brand new person: every submitted handle is new to them, so
    // withAddedAt(with no prior array) always stamps a fresh timestamp.
    const stampedHandles = contactHandles.map((handle) =>
      withAddedAt([], handle),
    );
    const attributes = structuredAttributeFields(args);
    const now = Date.now();
    const personId = await ctx.db.insert("people", {
      userId,
      name,
      normalizedName: normalizeName(name),
      context: args.context,
      contactHandles: stampedHandles,
      preferredPlatform,
      photoStorageId: args.photoStorageId,
      ...attributes,
      searchText: personSearchText({
        name,
        company: attributes.company,
        role: attributes.role,
        city: attributes.city,
        contactHandles: stampedHandles,
        context: args.context,
      }),
      updatedAt: now,
    });
    // Same transaction as the array, always: the index is only trustworthy
    // if it cannot drift from what the card shows.
    await insertPersonHandles(ctx, userId, personId, stampedHandles);
    await syncMemories(ctx, {
      userId,
      personId,
      context: args.context,
      createdAt: now,
    });
    await ctx.scheduler.runAfter(0, internal.people.embed, { personId });
    return { status: "created" as const, personId };
}

// The current contract: every dedup/attach/create outcome addPersonCore can
// reach, named explicitly so the caller can act on which one happened
// (open the new person, offer a merge on conflict, tell the user their note
// landed on someone they already knew). src/SearchAdd.tsx calls this one.
export const addPersonWithOutcome = mutation({
  args: {
    name: v.string(),
    context: v.optional(v.string()),
    contactHandles: v.optional(v.array(contactHandleValidator)),
    preferredPlatform: v.optional(v.string()),
    photoStorageId: v.optional(v.id("_storage")),
    attachToPersonId: v.optional(v.id("people")),
    ...structuredAttributeArgs,
  },
  returns: addPersonReturns,
  handler: async (ctx, args) => addPersonCore(ctx, args),
});

// The legacy contract, restored: an open SPA tab from before this mutation
// ever returned an outcome object calls "people:addPerson" by that literal
// registered name and assigns the result straight to a person id --
// `const id = await addPerson(...)`. Assigning an outcome OBJECT to that
// binding would not throw (JavaScript does not care), it would just quietly
// corrupt whatever that id was used for next -- a broken save with no error
// message anywhere. Kept as its own mutation, not a v.union return, because
// the shape a client decodes has to be exactly what the tab already
// deployed expects, not a superset it merely tolerates.
//
// Every dedup/attach/provenance behavior addPersonCore has still runs; an
// old tab just cannot see WHICH of created/attached/already happened (it
// gets silent dedup: an "attached" or "already" outcome quietly hands back
// the existing person's id) or pick a winner on conflict (there is no
// bare-id answer for "two different people," so this throws instead --
// nothing is written either way, and the tab's own error handling, built
// long before conflict existed, already has to survive an unexpected throw
// from this call).
export const addPerson = mutation({
  args: {
    name: v.string(),
    context: v.optional(v.string()),
    contactHandles: v.optional(v.array(contactHandleValidator)),
    preferredPlatform: v.optional(v.string()),
    photoStorageId: v.optional(v.id("_storage")),
    ...structuredAttributeArgs,
  },
  returns: v.id("people"),
  handler: async (ctx, args) => {
    const outcome = await addPersonCore(ctx, args);
    if (outcome.status === "conflict") {
      throw new Error(
        "That handle already belongs to two different people. Open one of them to add this note.",
      );
    }
    return outcome.personId;
  },
});

// How many of the caller's people this loads in full for client-side typo
// matching (src/nameSuggestion.ts). Personal directories are small
// pre-launch, so this is a generous cap, not a real limit anyone is
// expected to hit -- if it ever needs raising, the answer is pagination,
// not doubling the number.
const SUGGESTION_POOL_LIMIT = 2000;

// Convex's own search index (searchPeople below) does not typo-match, and
// the sky's own subscriptions are either scoped to a query or capped at the
// 20 most recent -- neither is a pool a client can run its own edit-distance
// suggester over and expect a mistyped name to surface. This is that pool:
// name and handles only (a suggestion row's disambiguator, nothing else),
// so loading every one of the caller's people stays cheap.
export const listPersonNames = query({
  args: {},
  returns: v.array(
    v.object({
      _id: v.id("people"),
      name: v.string(),
      contactHandles: v.optional(v.array(contactHandleValidator)),
    }),
  ),
  handler: async (ctx) => {
    const userId = await requireUser(ctx);
    const people = await ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .take(SUGGESTION_POOL_LIMIT);
    return people.map((person) => ({
      _id: person._id,
      name: person.name,
      contactHandles: person.contactHandles,
    }));
  },
});

export const searchPeople = query({
  args: { query: v.string() },
  returns: v.array(personValidator),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    // A query of only combining marks/punctuation can normalize to "" --
    // treat that the same as an empty query rather than search for "".
    const normalizedTerm = normalizeName(args.query);
    const people =
      normalizedTerm === ""
        ? await ctx.db
            .query("people")
            .withIndex("by_user", (q) => q.eq("userId", userId))
            .order("desc")
            .take(RESULT_LIMIT)
        : await ctx.db
            .query("people")
            .withSearchIndex("search_normalized_name", (q) =>
              q.search("normalizedName", normalizedTerm).eq("userId", userId),
            )
            .take(RESULT_LIMIT);
    return await Promise.all(people.map((person) => projectPerson(ctx, person)));
  },
});

// The Directory home screen: one page of the caller's people, most recently
// touched first. Recency exists to keep the screen useful, never as a
// closeness signal (design principles).
export const listPeople = query({
  args: { paginationOpts: paginationOptsValidator },
  returns: paginationResultValidator(personValidator),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const result = await ctx.db
      .query("people")
      .withIndex("by_user_and_updatedAt", (q) => q.eq("userId", userId))
      .order("desc")
      .paginate(args.paginationOpts);
    return {
      ...result,
      page: await Promise.all(
        result.page.map((person) => projectPerson(ctx, person)),
      ),
    };
  },
});

// The MVP search contract (mvp-design): chips over company, city, and role,
// combined with keywords over the card and notes. Chips arrive as display
// values and fold to keys server-side, so "Sai Gon" and "S\u00e0i G\u00f2n" (escaped)
// are the same chip. No fragment at all falls back to the recent directory,
// so the screen is never empty-handed.
export const searchDirectory = query({
  args: {
    keyword: v.optional(v.string()),
    company: v.optional(v.string()),
    city: v.optional(v.string()),
    role: v.optional(v.string()),
  },
  returns: v.array(personValidator),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    // A chip that folds to nothing (only punctuation/marks) is no chip:
    // rows never store an empty key, so matching "" would silently mean
    // "match nobody" instead of "ignore this chip".
    const chipKey = (raw: string | undefined) => {
      if (raw === undefined) {
        return undefined;
      }
      const key = normalizeName(raw);
      return key === "" ? undefined : key;
    };
    const keyword = normalizeName(args.keyword ?? "");
    const companyKey = chipKey(args.company);
    const cityKey = chipKey(args.city);
    const roleKey = chipKey(args.role);

    if (keyword !== "") {
      const people = await ctx.db
        .query("people")
        .withSearchIndex("search_text", (q) => {
          let search = q.search("searchText", keyword).eq("userId", userId);
          if (companyKey !== undefined) {
            search = search.eq("companyKey", companyKey);
          }
          if (cityKey !== undefined) {
            search = search.eq("cityKey", cityKey);
          }
          if (roleKey !== undefined) {
            search = search.eq("roleKey", roleKey);
          }
          return search;
        })
        .take(RESULT_LIMIT);
      return await Promise.all(
        people.map((person) => projectPerson(ctx, person)),
      );
    }

    // Chip-only: range on the most selective chip's index and post-filter
    // the rest. The filter does not shrink rows read, but the range is
    // already bounded to one user and one chip value.
    const indexed =
      companyKey !== undefined
        ? ctx.db
            .query("people")
            .withIndex("by_user_and_companyKey", (q) =>
              q.eq("userId", userId).eq("companyKey", companyKey),
            )
        : cityKey !== undefined
          ? ctx.db
              .query("people")
              .withIndex("by_user_and_cityKey", (q) =>
                q.eq("userId", userId).eq("cityKey", cityKey),
              )
          : roleKey !== undefined
            ? ctx.db
                .query("people")
                .withIndex("by_user_and_roleKey", (q) =>
                  q.eq("userId", userId).eq("roleKey", roleKey),
                )
            : null;
    if (indexed === null) {
      const recent = await ctx.db
        .query("people")
        .withIndex("by_user_and_updatedAt", (q) => q.eq("userId", userId))
        .order("desc")
        .take(RESULT_LIMIT);
      return await Promise.all(
        recent.map((person) => projectPerson(ctx, person)),
      );
    }
    const people = await indexed
      .order("desc")
      .filter((q) =>
        q.and(
          companyKey === undefined
            ? true
            : q.eq(q.field("companyKey"), companyKey),
          cityKey === undefined ? true : q.eq(q.field("cityKey"), cityKey),
          roleKey === undefined ? true : q.eq(q.field("roleKey"), roleKey),
        ),
      )
      .take(RESULT_LIMIT);
    return await Promise.all(people.map((person) => projectPerson(ctx, person)));
  },
});

const facetValidator = v.object({ value: v.string(), count: v.number() });

// Bounded honestly: only the FACET_SCAN_LIMIT most recently touched people
// are counted, so past that size the counts go approximate. The upgrade
// path, if a directory ever outgrows this, is denormalized per-user facet
// counters maintained by the mutations.
const FACET_SCAN_LIMIT = 1000;
const FACET_LIMIT = 30;

// The values behind the search screen's chips, drawn from the caller's own
// directory. Case and accent variants collapse into one chip (by derived
// key); the most recently used spelling is the label.
export const directoryFacets = query({
  args: {},
  returns: v.object({
    companies: v.array(facetValidator),
    cities: v.array(facetValidator),
    roles: v.array(facetValidator),
  }),
  handler: async (ctx) => {
    const userId = await requireUser(ctx);
    const people = await ctx.db
      .query("people")
      .withIndex("by_user_and_updatedAt", (q) => q.eq("userId", userId))
      .order("desc")
      .take(FACET_SCAN_LIMIT);

    const collect = (
      entries: Array<{ key?: string; label?: string }>,
    ): Array<{ value: string; count: number }> => {
      const byKey = new Map<string, { value: string; count: number }>();
      for (const { key, label } of entries) {
        if (key === undefined || label === undefined) {
          continue;
        }
        const existing = byKey.get(key);
        if (existing === undefined) {
          // First sighting in a newest-first scan: the freshest spelling
          // becomes the label.
          byKey.set(key, { value: label, count: 1 });
        } else {
          existing.count++;
        }
      }
      // Sort is stable, so equal counts keep their newest-first order.
      return [...byKey.values()]
        .sort((a, b) => b.count - a.count)
        .slice(0, FACET_LIMIT);
    };

    return {
      companies: collect(
        people.map((p) => ({ key: p.companyKey, label: p.company })),
      ),
      cities: collect(
        people.map((p) => ({ key: p.cityKey, label: p.city?.name })),
      ),
      roles: collect(people.map((p) => ({ key: p.roleKey, label: p.role }))),
    };
  },
});

// The peer's own ways to be reached, under the owner's layer. Display only:
// writing them into contactHandles would put rows in the identity index the
// owner never saved, and a handle the peer later drops could never be taken
// back out of the owner's row.
//
// Nothing is withheld. The public web card strips phone because getByHandle
// answers strangers; a connection is someone who confirmed this person in
// person, and mvp-design's contacts overlay renders "their canonical data
// plus your layer" whole. Per-field control is the roadmap's selective card
// sharing, deliberately post-v1.
function mergePeerHandles(
  own: ContactHandleInput[] | undefined,
  peer: { platform: string; value: string }[] | undefined,
): ContactHandleInput[] | undefined {
  if (peer === undefined || peer.length === 0) {
    return own;
  }
  const mine = own ?? [];
  const held = new Set(mine.map((handle) => handle.platform));
  return [
    ...mine,
    ...peer
      .filter((handle) => !held.has(handle.platform))
      .map((handle) => ({ platform: handle.platform, value: handle.value })),
  ];
}

// A connected Haven user's card is theirs and stays current; the notes and
// the photo you attached are yours. Reference rather than copy is the whole
// point -- copying at connect time is what lets contacts go stale, which is
// the problem Haven exists to solve (mvp-design).
//
// Only the detail read merges. A directory page would turn into one profile
// read per row, and the snapshot written at connect time is what keeps lists
// and search readable in the meantime.
async function projectConnectedPerson(ctx: QueryCtx, person: Doc<"people">) {
  const projected = await projectPerson(ctx, person);
  // A frozen row still names the peer, so that a reconnection can thaw it,
  // but freezing is exactly the promise that it has stopped following them.
  if (
    person.havenContactUserId === undefined ||
    person.connectionEndedAt !== undefined
  ) {
    return projected;
  }
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_user", (q) => q.eq("userId", person.havenContactUserId!))
    .unique();
  if (profile === null) {
    // The account went before the sweep reached this row. Read it as the
    // frozen snapshot it is about to become rather than as a live reference.
    return projected;
  }
  return {
    ...projected,
    name: profile.name ?? projected.name,
    city: toCityInput(profile.city) ?? projected.city,
    company: profile.company ?? projected.company,
    role: profile.role ?? projected.role,
    // Their address is theirs too, and the snapshot fan-out that keeps the
    // row's copy current is scheduled work: on this read the live one is
    // free and cannot lag.
    connection: { state: "connected" as const, peerUsername: profile.username },
    contactHandles: mergePeerHandles(person.contactHandles, profile.handles),
    preferredPlatform: person.preferredPlatform ?? profile.primaryPlatform,
    // Your own photo of them wins: that is your layer, not their card.
    photoUrl:
      person.photoStorageId !== undefined
        ? projected.photoUrl
        : profile.photoStorageId === undefined
          ? projected.photoUrl
          : await ctx.storage.getUrl(profile.photoStorageId),
  };
}

export const getPerson = query({
  args: { id: v.id("people") },
  returns: v.union(v.null(), personValidator),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const person = await ctx.db.get("people", args.id);
    if (person === null || person.userId !== userId) {
      return null;
    }
    return await projectConnectedPerson(ctx, person);
  },
});

export const updatePerson = mutation({
  args: {
    id: v.id("people"),
    link: v.optional(v.string()),
    context: v.optional(v.string()),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "updatePerson", 60, MINUTE_MS);
    const person = await ctx.db.get("people", args.id);
    if (person === null || person.userId !== userId) {
      throw new Error("Person not found");
    }
    if (args.context !== undefined && args.context.length > MAX_CONTEXT_LENGTH) {
      throw new Error(CONTEXT_TOO_LONG_ERROR);
    }
    // The detail screen always sends both fields; an omitted (undefined) value
    // means the user cleared that input, so patch unsets the field on purpose.
    // Callers that want to leave a field untouched must resend its current value.
    // updatePerson never takes a name, so normalizedName (set at insert) is
    // never stale here and does not need recomputing.
    const now = Date.now();
    await ctx.db.patch("people", args.id, {
      link: args.link,
      context: args.context,
      searchText: personSearchText({ ...person, context: args.context }),
      updatedAt: now,
    });
    await syncMemories(ctx, {
      userId,
      personId: args.id,
      context: args.context,
      createdAt: now,
    });
    await ctx.scheduler.runAfter(0, internal.people.embed, {
      personId: args.id,
    });
    return null;
  },
});

// The iOS contact editor. An omitted field is left alone; an explicit null
// clears it -- the same contract as profiles.updateMyProfile. Name is the
// one field with no null, because a person cannot exist without one. The
// legacy web detail screen keeps updatePerson's send-everything semantics
// above; the two contracts must not be merged.
export const editPerson = mutation({
  args: {
    id: v.id("people"),
    name: v.optional(v.string()),
    link: v.optional(v.union(v.string(), v.null())),
    context: v.optional(v.union(v.string(), v.null())),
    contactHandles: v.optional(v.array(contactHandleValidator)),
    preferredPlatform: v.optional(v.union(v.string(), v.null())),
    photoStorageId: v.optional(v.union(v.id("_storage"), v.null())),
    city: v.optional(v.union(cityInputValidator, v.null())),
    company: v.optional(v.union(v.string(), v.null())),
    role: v.optional(v.union(v.string(), v.null())),
  },
  returns: v.union(
    personValidator,
    v.object({
      status: v.literal("handle_taken"),
      personId: v.id("people"),
      name: v.string(),
    }),
  ),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "editPerson", 60, MINUTE_MS);
    const person = await ctx.db.get("people", args.id);
    if (person === null || person.userId !== userId) {
      throw new Error("Person not found");
    }

    const fields: Partial<Doc<"people">> = {};
    if (args.name !== undefined) {
      const name = args.name.trim();
      if (name === "") {
        throw new Error("Name is required");
      }
      requireWithin("a name", name, CARD_NAME_MAX);
      fields.name = name;
      // A rename that skips this leaves the person findable only under the
      // old name.
      fields.normalizedName = normalizeName(name);
    }
    if (args.link !== undefined) {
      fields.link = args.link ?? undefined;
    }
    if (args.context !== undefined) {
      if (args.context !== null && args.context.length > MAX_CONTEXT_LENGTH) {
        throw new Error(CONTEXT_TOO_LONG_ERROR);
      }
      fields.context = args.context ?? undefined;
    }
    // A cleared attribute drops its derived key too, or the chip filter
    // would keep matching a value the card no longer shows.
    if (args.company !== undefined) {
      if (args.company === null) {
        fields.company = undefined;
        fields.companyKey = undefined;
      } else {
        Object.assign(
          fields,
          structuredAttributeFields({ company: args.company }),
        );
      }
    }
    if (args.role !== undefined) {
      if (args.role === null) {
        fields.role = undefined;
        fields.roleKey = undefined;
      } else {
        Object.assign(fields, structuredAttributeFields({ role: args.role }));
      }
    }
    if (args.city !== undefined) {
      if (args.city === null) {
        fields.city = undefined;
        fields.cityKey = undefined;
      } else {
        Object.assign(fields, structuredAttributeFields({ city: args.city }));
      }
    }
    if (args.contactHandles !== undefined) {
      // Folded, capped and length-checked the same way validateOwnedHandles
      // does (one call, so the "at most MAX_CONTACT_HANDLES total" and "one
      // handle per platform" checks still see the whole submitted array) --
      // but NOT yet defaulted to "typed": a client that only reorders or
      // re-saves an unrelated field (iOS's PersonFieldEditors sends bare
      // {platform, value} for every handle, not just the one that changed)
      // must not have that read as a fresh, hand-typed entry for a handle
      // that was actually proven months ago. Whether this is the same
      // account decides that below, per handle.
      const candidateHandles = validateContactHandles(args.contactHandles).map(
        (handle) => {
          requireWithin("a handle", handle.value, HANDLE_MAX);
          return handle;
        },
      );
      // A handle already on this same person is a re-save, not a theft:
      // only a DIFFERENT owner blocks the write. Checked before anything is
      // touched, including the photo swap below, so a taken handle leaves
      // the row exactly as it was. platformId-first, same as addPerson, so
      // a rename of this person's own handle never misreads as someone
      // else's account.
      const previousHandles = person.contactHandles ?? [];
      for (const handle of candidateHandles) {
        const keys = handleIndexKeys(handle);
        const owner = await findHandleOwner(
          ctx,
          userId,
          keys.platform,
          keys.valueKey,
          handle.platformId,
        );
        if (owner !== null && owner._id !== args.id) {
          return {
            status: "handle_taken" as const,
            personId: owner._id,
            name: owner.name,
          };
        }
        // findHandleOwner stops at its first hit: a platformId match short
        // circuits before it ever tries the value on its own. When that hit
        // is this same person, this is a rename in place (the id proves the
        // account, the new value is the claim) -- exactly the case
        // mergeHandleIntoOwner's own rename branch guards elsewhere, but
        // this rewrite is editPerson's own wholesale replace, not a merge,
        // so it needs the same question asked here: does somebody else
        // already hold that value outright? Skipped when owner is null,
        // since findHandleOwner's internal fallback already tried the value
        // lookup on its own in that case and found nobody either way.
        if (owner !== null && handle.platformId !== undefined) {
          const valueOwner = await findHandleOwner(
            ctx,
            userId,
            keys.platform,
            keys.valueKey,
          );
          if (valueOwner !== null && valueOwner._id !== args.id) {
            return {
              status: "handle_taken" as const,
              personId: valueOwner._id,
              name: valueOwner.name,
            };
          }
        }
        // W2: equal value, but this submission's platformId disagrees with
        // what THIS person's own handle already had proven -- the id-vs-id
        // conflict the two checks above cannot see, because both of them
        // ask "does somebody else own this," and here nobody else does.
        // mergeHandleIntoOwner's own equal-valueKey branch (people.ts)
        // treats the exact same shape -- both ids present and differing on
        // an equal value -- as username-reassignment evidence, not a
        // rename of this account, and refuses rather than overwrite the
        // proof. There is no other Haven person to name, so this mirrors
        // that branch's naming: personId/name point back at this same
        // person. An absent platformId (a bare {platform, value} resubmit,
        // S1's carry-forward case) never reaches this check at all.
        const priorMatch = previousHandles.find((existing) => {
          const existingKeys = handleIndexKeys(existing);
          return (
            existingKeys.platform === keys.platform &&
            existingKeys.valueKey === keys.valueKey
          );
        });
        if (
          priorMatch !== undefined &&
          priorMatch.platformId !== undefined &&
          handle.platformId !== undefined &&
          priorMatch.platformId !== handle.platformId
        ) {
          return {
            status: "handle_taken" as const,
            personId: args.id,
            name: person.name,
          };
        }
      }
      // The array is rewritten wholesale below. For each submitted handle,
      // find the entry already on this person for the SAME (platform,
      // valueKey) -- the same account, not merely the same platform slot --
      // and carry its source/platformId/addedAt forward unless this
      // submission explicitly brings its own (an editor that DOES know a
      // fresher platformId, e.g. the X-rename flow, still gets to set it).
      // No prior match means either a brand new platform for this person or
      // a changed value on an existing one -- a different account either
      // way, so nothing carries over and "typed" is the one source this
      // file is certain of when the caller does not say otherwise.
      fields.contactHandles = candidateHandles.map((handle) => {
        const keys = handleIndexKeys(handle);
        const priorMatch = previousHandles.find((existing) => {
          const existingKeys = handleIndexKeys(existing);
          return (
            existingKeys.platform === keys.platform &&
            existingKeys.valueKey === keys.valueKey
          );
        });
        if (priorMatch !== undefined) {
          return {
            ...handle,
            source: handle.source ?? priorMatch.source,
            platformId: handle.platformId ?? priorMatch.platformId,
            addedAt: handle.addedAt ?? priorMatch.addedAt ?? Date.now(),
          };
        }
        return {
          ...handle,
          source: handle.source ?? "typed",
          addedAt: handle.addedAt ?? Date.now(),
        };
      });
    }

    // The preferred platform must point at a handle that exists once this
    // write lands, so it is checked against the merged list, not the args.
    const nextHandles = fields.contactHandles ?? person.contactHandles ?? [];
    if (args.preferredPlatform !== undefined) {
      fields.preferredPlatform =
        args.preferredPlatform === null
          ? undefined
          : validatePreferredPlatform(args.preferredPlatform, nextHandles);
    } else if (
      person.preferredPlatform !== undefined &&
      !nextHandles.some(
        (handle) => handle.platform === person.preferredPlatform,
      )
    ) {
      // Removing the preferred handle clears the pointer instead of
      // dangling it.
      fields.preferredPlatform = undefined;
    }

    if (args.photoStorageId !== undefined) {
      if (args.photoStorageId !== null) {
        await requireImageBlob(ctx, args.photoStorageId, PHOTO_ERROR);
      }
      const next = args.photoStorageId ?? undefined;
      // Deleting works here, unlike on a throwing path: this commits, and a
      // replaced blob would otherwise be unreachable until the orphan sweep.
      if (
        person.photoStorageId !== undefined &&
        person.photoStorageId !== next
      ) {
        await ctx.storage.delete(person.photoStorageId);
      }
      fields.photoStorageId = next;
    }

    // Recomputed from the merged next state, so a cleared field's words stop
    // matching the moment the edit lands.
    fields.searchText = personSearchText({ ...person, ...fields });

    const now = Date.now();
    await ctx.db.patch("people", args.id, { ...fields, updatedAt: now });
    // A replaced array is rewritten wholesale rather than diffed: the list is
    // capped at 8, so a full rewrite is the same cost and cannot mis-diff.
    if (fields.contactHandles !== undefined) {
      await deletePersonHandles(ctx, args.id);
      await insertPersonHandles(ctx, userId, args.id, fields.contactHandles);
    }
    await syncMemories(ctx, {
      userId,
      personId: args.id,
      context: fields.context,
      createdAt: now,
    });
    await ctx.scheduler.runAfter(0, internal.people.embed, {
      personId: args.id,
    });
    const updated = await ctx.db.get("people", args.id);
    if (updated === null) {
      throw new Error("Could not save person");
    }
    return await projectPerson(ctx, updated);
  },
});

// Throwing away a contact who is a connection ends the connection, through
// the same teardown profiles.disconnect uses: the edge and the co-written
// shared note go, and the other side's row freezes to the snapshot they own
// rather than being left pointing at a connection that no longer exists.
export const deletePerson = mutation({
  args: { personId: v.id("people") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const person = await ctx.db.get("people", args.personId);
    if (person === null || person.userId !== userId) {
      throw new Error("Person not found");
    }
    if (person.screenshotId !== undefined) {
      await ctx.storage.delete(person.screenshotId);
    }
    if (person.photoStorageId !== undefined) {
      await ctx.storage.delete(person.photoStorageId);
    }
    // Ghost index rows would resurrect a deleted person in every handle
    // lookup, and orphaned memories would keep matching in semantic search
    // for somebody the user deleted. Both go with the person.
    await deletePersonHandles(ctx, args.personId);
    await deleteMemories(ctx, args.personId);
    await endConnection(ctx, userId, args.personId, Date.now());
    await ctx.db.delete("people", args.personId);
    return null;
  },
});

// ------------------------------------------------- shared profile capture

// A profile shared from Instagram, LinkedIn, or X becomes a real person
// immediately -- there is nothing asynchronous to stage (capture-pipeline
// plan). Idempotent on (platform, handle) per the repo's creation
// convention, and the outcome tells the share sheet what to say.
export const saveSharedProfile = mutation({
  args: {
    platform: v.string(),
    handleValue: v.string(),
    profileUrl: v.string(),
    name: v.string(),
    note: v.optional(v.string()),
    attachToPersonId: v.optional(v.id("people")),
    // Both optional: a caller with nothing to say about provenance (most of
    // them, today) gets legacy behavior -- source stored as given, undefined
    // when omitted, never guessed at "typed" the way a hand-entered form
    // defaults, because a share is not something anyone typed here.
    source: v.optional(handleSourceValidator),
    platformId: v.optional(v.string()),
  },
  returns: v.object({
    status: v.union(
      v.literal("created"),
      v.literal("already"),
      v.literal("attached"),
      v.literal("conflict"),
    ),
    // A single flat shape rather than a discriminated union, deliberately:
    // iOS's SharedProfileOutcome (CaptureDrain.swift) is a plain Decodable
    // struct with no CodingKeys, so it only ever reads status and
    // noteTruncated and requires personId on every response it can decode.
    // "conflict" still fills personId -- with the handle's true owner, not
    // the caller's guess -- so an old client that never learns about
    // "conflict" still gets a person id it can act on instead of a decode
    // failure that redrains this capture forever.
    personId: v.id("people"),
    // True when the context cap cut the note: the capture landed, but the
    // drain should surface the loss instead of reporting a complete save.
    noteTruncated: v.boolean(),
    // True when the account this share names could not fit under the
    // 8-handle cap on the person it landed on. Only "already" and "attached"
    // can ever set it: "created" always has room for the one handle it is
    // made of, and "conflict" never writes anything.
    handleDropped: v.boolean(),
    // Set only on "conflict": the person the caller asked to attach to,
    // which this save did NOT use because the handle already, provably,
    // belongs to someone else (personId above). Additive -- a client that
    // does not know this field yet just sees personId and moves on.
    conflictPersonId: v.optional(v.id("people")),
  }),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "saveSharedProfile", 30, MINUTE_MS);

    // The stored value carries the same shape as its identity key: a share of
    // "@mai.makes" and one of "mai.makes" must render and search alike, not
    // just dedup alike. validateContactHandles owns the platform fold and the
    // blank checks, same as every other handle write path.
    const [handle] = validateContactHandles([
      {
        platform: args.platform,
        value: handleDisplayValue(args.handleValue),
        source: args.source,
        platformId: args.platformId,
      },
    ]);
    const { platform, value } = handle;
    const valueKey = handleValueKey(value, platform);
    const name = args.name.trim();
    if (name === "") {
      throw new Error("Name is required");
    }
    const trimmedNote = args.note?.trim();
    const note =
      trimmedNote === undefined || trimmedNote === "" ? undefined : trimmedNote;
    const profileUrl = args.profileUrl.trim();

    // Two owners of one handle is still corruption -- addPerson and
    // editPerson now gate new writes so this cannot happen going forward,
    // but a row from before that gate, or from a path this file does not
    // cover, can still leave two. This drains unattended (the share sheet,
    // a queued capture), so a throw here would jam the queue on corruption
    // nobody present can fix; findHandleOwner attaches to the oldest row
    // deterministically and logs the rest for reportDuplicateHandleOwners to
    // surface instead. platformId-first: a re-share of a renamed account
    // still finds the same person.
    const owner = await findHandleOwner(
      ctx,
      userId,
      platform,
      valueKey,
      handle.platformId,
    );
    if (owner !== null) {
      if (
        args.attachToPersonId !== undefined &&
        args.attachToPersonId !== owner._id
      ) {
        // The caller answered "same person?" for a specific person, but this
        // handle is already, provably, somebody else's -- silently landing
        // the note there anyway would be exactly the identity theft this
        // whole file exists to prevent. Nothing is written on this branch;
        // the true owner is handed back so the caller can react (offer a
        // merge, or ask again) instead of the capture just vanishing onto
        // the wrong card.
        return {
          status: "conflict" as const,
          personId: owner._id,
          noteTruncated: false,
          handleDropped: false,
          conflictPersonId: args.attachToPersonId,
        };
      }
      // Handle identity beats the attach target: this account provably
      // belongs to this person, however stale the caller's mirror is.
      // mergeHandleIntoOwner updates the stored value in place when this
      // owner was found by platformId but the username has since changed --
      // the rename-following behavior the product wants -- and is a no-op
      // when the share is byte-identical to what is already stored.
      const replacingSamePlatformHandle = (owner.contactHandles ?? []).some(
        (existing) => {
          const keys = handleIndexKeys(existing);
          return keys.platform === platform && keys.valueKey !== valueKey;
        },
      );
      const merged = await mergeHandleIntoOwner(
        ctx,
        userId,
        owner,
        owner.contactHandles ?? [],
        handle,
      );
      if (merged.status === "refused") {
        // The id says this is `owner`; the username the share carries
        // already belongs to somebody else. Nothing written, same as the
        // attachToPersonId mismatch above -- both are "two different
        // people disagree about who this is" and get the same answer.
        return {
          status: "conflict" as const,
          personId: owner._id,
          noteTruncated: false,
          handleDropped: false,
          conflictPersonId: merged.conflictingOwnerId,
        };
      }
      const fields: Partial<Doc<"people">> = {};
      const { context, noteTruncated } = appendContext(owner.context, note);
      if (context !== owner.context) {
        fields.context = context;
      }
      if (merged.changed) {
        fields.contactHandles = merged.handles;
      }
      Object.assign(
        fields,
        linkBackfill(owner, profileUrl, replacingSamePlatformHandle),
      );
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
      } else {
        // Nothing changed, but a formula change since the row was written can
        // leave searchText stale; the re-share is the one moment the row is
        // in hand to heal it. A heal is not an edit: updatedAt stays put.
        const searchText = personSearchText(owner);
        if (searchText !== owner.searchText) {
          await ctx.db.patch("people", owner._id, { searchText });
        }
      }
      return {
        status: "already" as const,
        personId: owner._id,
        noteTruncated,
        handleDropped: merged.handleDropped,
      };
    }

    if (args.attachToPersonId !== undefined) {
      const target = await ctx.db.get("people", args.attachToPersonId);
      // A target that is gone or somebody else's falls through to create:
      // the extension's mirror can be days stale and a capture is never lost.
      if (target !== null && target.userId === userId) {
        const targetHandles = target.contactHandles ?? [];
        // `attachToPersonId` is the person's explicit "same person" answer.
        // That is the proof LinkedIn rename handling needs because LinkedIn
        // exposes no stable account id: replace the old slug on the selected
        // person, but still let mergeHandleIntoOwner refuse if the new value
        // is already proven to belong to somebody else.
        const replacingSamePlatformHandle = targetHandles.some((existing) => {
          const keys = handleIndexKeys(existing);
          return keys.platform === platform && keys.valueKey !== valueKey;
        });
        const merged = await mergeHandleIntoOwner(
          ctx,
          userId,
          target,
          targetHandles,
          handle,
        );
        if (merged.status === "refused") {
          return {
            status: "conflict" as const,
            personId: merged.conflictingOwnerId,
            noteTruncated: false,
            handleDropped: false,
            conflictPersonId: target._id,
          };
        }
        const { context, noteTruncated } = appendContext(
          target.context,
          note,
        );
        const fields: Partial<Doc<"people">> = {
          context,
          ...linkBackfill(
            target,
            profileUrl,
            replacingSamePlatformHandle,
          ),
        };
        if (merged.changed) {
          fields.contactHandles = merged.handles;
        }
        const now = Date.now();
        await ctx.db.patch("people", target._id, {
          ...fields,
          searchText: personSearchText({ ...target, ...fields }),
          updatedAt: now,
        });
        if (merged.changed) {
          // Inserted even when the array already held this handle: that
          // only happens for a person written before this index existed.
          await deletePersonHandles(ctx, target._id);
          await insertPersonHandles(ctx, userId, target._id, merged.handles);
        }
        await syncMemories(ctx, {
          userId,
          personId: target._id,
          context: fields.context,
          createdAt: now,
        });
        await ctx.scheduler.runAfter(0, internal.people.embed, {
          personId: target._id,
        });
        return {
          status: "attached" as const,
          personId: target._id,
          noteTruncated,
          handleDropped: merged.handleDropped,
        };
      }
    }

    const contactHandles = [withAddedAt([], handle)];
    // Through appendContext even with nothing to append to, so the clamp
    // policy lives in exactly one place.
    const { context, noteTruncated } = appendContext(undefined, note);
    const now = Date.now();
    const personId = await ctx.db.insert("people", {
      userId,
      name,
      normalizedName: normalizeName(name),
      context,
      link: profileUrl === "" ? undefined : profileUrl,
      contactHandles,
      // preferredPlatform stays unset: the share sheet never asks how the
      // user wants to reach this person.
      searchText: personSearchText({ name, contactHandles, context }),
      updatedAt: now,
    });
    await insertPersonHandles(ctx, userId, personId, contactHandles);
    await syncMemories(ctx, { userId, personId, context, createdAt: now });
    await ctx.scheduler.runAfter(0, internal.people.embed, { personId });
    return {
      status: "created" as const,
      personId,
      noteTruncated,
      handleDropped: false,
    };
  },
});

// ------------------------------------------------------------- embeddings

export const getPersonInternal = internalQuery({
  args: { id: v.id("people") },
  handler: async (ctx, args) => {
    return await ctx.db.get("people", args.id);
  },
});

// Writes an X account's stable platform id onto the person's existing x
// handle, once composio.ts's resolveXPlatformId has proven it. Deliberately
// narrow: this patches one field on one already-present handle, it never
// creates a handle, changes a value, or touches any other platform.
//
// Both authz and the username-still-matches guard are re-checked here, not
// only in the calling action: two Composio network calls run between the
// action's own checks and this write landing, and either the person could
// stop belonging to the caller or the card's x handle could be renamed in
// that gap. Writing a stale username's id onto a since-renamed handle is
// exactly the bug rename-proofing exists to prevent, so a mismatch is a
// silent no-op rather than a write of what the caller asked for a moment ago
// but is no longer true.
export const patchXPlatformId = internalMutation({
  args: {
    personId: v.id("people"),
    username: v.string(),
    platformId: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    // Derived here rather than trusted from the caller (guidelines.md's
    // authentication rule: never accept a userId as an argument for
    // authorization). Auth propagates through ctx.runMutation from the
    // calling action -- composio.ts's resolveXPlatformId already proved
    // this identity with its own requireUser call a moment earlier: this is
    // the same request, not a fresh one that could disagree.
    const userId = await requireUser(ctx);
    const person = await ctx.db.get("people", args.personId);
    if (person === null || person.userId !== userId) {
      return null;
    }
    const handles = person.contactHandles ?? [];
    const index = handles.findIndex((handle) => handle.platform === "x");
    if (index === -1) {
      return null;
    }
    const existing = handles[index];
    if (handleValueKey(existing.value, "x") !== handleValueKey(args.username, "x")) {
      return null;
    }
    // W3: the value still matches, but this handle already had a DIFFERENT
    // id proven -- the same username-reassignment shape mergeHandleIntoOwner's
    // X1 rule and editPerson's own guard (W2) refuse elsewhere. Compared
    // directly rather than through findHandleOwner below: that lookup only
    // answers "does somebody ELSE own id-new," and here nobody does yet
    // (Composio just resolved it) -- the disagreement is with THIS handle's
    // own prior proof, which only a direct comparison catches.
    if (existing.platformId !== undefined && existing.platformId !== args.platformId) {
      console.error(
        `patchXPlatformId: stored platformId for x disagrees with the resolved one (person=${args.personId}), skipping`,
      );
      return null;
    }
    // The X id resolves AFTER the save (composio.ts's resolveXPlatformId
    // runs fire-and-forget once the person already exists), so the
    // platformId-first dedup in findHandleOwner never got a chance to see
    // it at write time. If this exact id already belongs to a DIFFERENT one
    // of this user's people -- two saves for the same X account, landed as
    // two people some other way -- stamping it here a second time would be
    // exactly the corruption findHandleOwner's own platformId index exists
    // to prevent. Refused, not merged: nobody asked this write to reconcile
    // two people into one, only to prove an id.
    const existingOwner = await findHandleOwner(
      ctx,
      userId,
      "x",
      handleValueKey(args.username, "x"),
      args.platformId,
    );
    if (existingOwner !== null && existingOwner._id !== args.personId) {
      console.error(
        `patchXPlatformId: platformId for x already belongs to a different person (owner=${existingOwner._id}, target=${args.personId}), skipping`,
      );
      return null;
    }
    const nextHandles = [...handles];
    nextHandles[index] = { ...existing, platformId: args.platformId };
    await ctx.db.patch("people", args.personId, {
      contactHandles: nextHandles,
      updatedAt: Date.now(),
    });
    await deletePersonHandles(ctx, args.personId);
    await insertPersonHandles(ctx, userId, args.personId, nextHandles);
    return null;
  },
});

export const saveEmbedding = internalMutation({
  args: {
    id: v.id("people"),
    embedding: v.array(v.float64()),
    embeddedText: v.string(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const person = await ctx.db.get("people", args.id);
    if (person === null) {
      return null;
    }
    await ctx.db.patch("people", args.id, {
      embedding: args.embedding,
      embeddedText: args.embeddedText,
    });
    return null;
  },
});

// Shared by the embed action and the backfill (guidelines: do not call an
// action from an action in the same runtime; share a helper instead).
async function embedPerson(
  ctx: ActionCtx,
  personId: Id<"people">,
): Promise<void> {
  const person: Doc<"people"> | null = await ctx.runQuery(
    internal.people.getPersonInternal,
    { id: personId },
  );
  if (person === null) {
    return;
  }
  const text = buildEmbedText({
    name: person.name,
    platform: person.platform,
    handle: person.handle,
    headline: person.headline,
    bio: person.bio,
    role: person.role,
    company: person.company,
    cityName: person.city?.name,
    context: person.context,
  }).slice(0, MAX_EMBED_INPUT_LENGTH);
  // Idempotent: the stored (sliced) text is the key for the stored vector.
  if (person.embedding !== undefined && person.embeddedText === text) {
    return;
  }
  const embedding = await embedText(text);
  await ctx.runMutation(internal.people.saveEmbedding, {
    id: personId,
    embedding,
    embeddedText: text,
  });
}

export const embed = internalAction({
  args: { personId: v.id("people"), attempt: v.optional(v.number()) },
  returns: v.null(),
  handler: async (ctx, args) => {
    const attempt = args.attempt ?? 0;
    try {
      await embedPerson(ctx, args.personId);
    } catch (error) {
      const delayMs = EMBED_RETRY_DELAYS_MS[attempt];
      if (delayMs === undefined) {
        // Out of retries: log and give up rather than throw, so a single
        // stuck person can never surface as an unhandled action failure.
        console.error(
          `embed: giving up on person ${args.personId} after ${attempt + 1} attempts`,
          error,
        );
        return null;
      }
      await ctx.scheduler.runAfter(delayMs, internal.people.embed, {
        personId: args.personId,
        attempt: attempt + 1,
      });
    }
    return null;
  },
});

// ---------------------------------------------------------- semantic search

const searchResultValidator = v.object({
  _id: v.id("people"),
  _creationTime: v.number(),
  name: v.string(),
  link: v.optional(v.string()),
  context: v.optional(v.string()),
  platform: v.optional(v.string()),
  handle: v.optional(v.string()),
  headline: v.optional(v.string()),
  bio: v.optional(v.string()),
  score: v.number(),
  // The memory line that matched, when one did. Evidence is the trust
  // feature: a memory-search result without "matched because you wrote ..."
  // reads as random. Unset when only the person's own card vector matched,
  // because a single averaged vector cannot say which field earned the hit.
  evidence: v.optional(v.string()),
});

export const fetchSearchResults = internalQuery({
  args: { ids: v.array(v.id("people")) },
  handler: async (ctx, args) => {
    // Safe without an auth check: internal-only, and the ids come from a
    // vector search already filtered to the caller's userId.
    const people: Array<Doc<"people">> = [];
    for (const id of args.ids) {
      const person = await ctx.db.get("people", id);
      if (person !== null) {
        people.push(person);
      }
    }
    return people.map((person) => ({
      _id: person._id,
      _creationTime: person._creationTime,
      name: person.name,
      link: person.link,
      context: person.context,
      platform: person.platform,
      handle: person.handle,
      headline: person.headline,
      bio: person.bio,
    }));
  },
});

// Actions have no ctx.db (guidelines), so an action-side rate-limit check
// has to reach the DB through a mutation. userId here is the caller's own
// identity, derived server-side by the action just above -- not a
// client-supplied authorization key.
export const enforceRateLimit = internalMutation({
  args: {
    userId: v.string(),
    action: v.string(),
    max: v.number(),
    windowMs: v.number(),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    await checkRateLimit(ctx, args.userId, args.action, args.max, args.windowMs);
    return null;
  },
});

export const semanticSearch = action({
  args: { query: v.string() },
  returns: v.array(searchResultValidator),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await ctx.runMutation(internal.people.enforceRateLimit, {
      userId,
      action: "semanticSearch",
      max: 30,
      windowMs: MINUTE_MS,
    });
    const term = args.query.trim();
    if (term === "") {
      return [];
    }
    const vector = await embedText(term);
    // Two indexes, one query vector. Memories get the wider limit because
    // they are per-line: a chatty person holds many rows, and a slot budget
    // as small as the person one would let them crowd everyone else out
    // before the per-person aggregation below ever runs.
    const [personHits, memoryHits] = await Promise.all([
      ctx.vectorSearch("people", "by_embedding", {
        vector,
        limit: SEMANTIC_RESULT_LIMIT,
        filter: (q) => q.eq("userId", userId),
      }),
      ctx.vectorSearch("memories", "by_embedding", {
        vector,
        limit: MEMORY_CANDIDATE_LIMIT,
        filter: (q) => q.eq("userId", userId),
      }),
    ]);

    // Best score wins per person, and the memory that earned it is the
    // evidence. A person can be reached from both indexes; they appear once.
    const best = new Map<Id<"people">, { score: number; evidence?: string }>();
    const keepBest = (
      personId: Id<"people">,
      score: number,
      evidence?: string,
    ) => {
      const current = best.get(personId);
      if (current === undefined || score > current.score) {
        best.set(personId, { score, evidence });
      }
    };
    // Memories are aggregated first, and the person index only displaces one
    // on a strictly higher score: at a tie the result that can say "matched
    // because you wrote ..." is the more useful of the two. Vector search
    // returns descending order, so the same strict rule keeps the best
    // memory line among several a person owns.
    const strongMemories = memoryHits.filter(
      (hit) => hit._score >= MIN_SEMANTIC_SCORE,
    );
    if (strongMemories.length > 0) {
      const memoryScores = new Map(
        strongMemories.map((hit) => [hit._id, hit._score]),
      );
      const owners: Array<{
        _id: Id<"memories">;
        personId: Id<"people">;
        text: string;
      }> = await ctx.runQuery(internal.memories.fetchMemoryOwners, {
        ids: strongMemories.map((hit) => hit._id),
      });
      for (const owner of owners) {
        keepBest(owner.personId, memoryScores.get(owner._id) ?? 0, owner.text);
      }
    }
    for (const hit of personHits) {
      if (hit._score >= MIN_SEMANTIC_SCORE) {
        keepBest(hit._id, hit._score);
      }
    }
    // Ranked and cut before hydration, not after: the memory index alone can
    // name far more people than a page of results holds.
    const ranked = [...best.entries()]
      .sort(([, a], [, b]) => b.score - a.score)
      .slice(0, SEMANTIC_RESULT_LIMIT);
    if (ranked.length === 0) {
      return [];
    }
    const people: Array<{
      _id: Id<"people">;
      _creationTime: number;
      name: string;
      link?: string;
      context?: string;
      platform?: string;
      handle?: string;
      headline?: string;
      bio?: string;
    }> = await ctx.runQuery(internal.people.fetchSearchResults, {
      ids: ranked.map(([personId]) => personId),
    });
    const byId = new Map(people.map((person) => [person._id, person]));
    // flatMap, so a person deleted between the vector search and this read
    // drops out rather than surfacing as a hole.
    return ranked.flatMap(([personId, { score, evidence }]) => {
      const person = byId.get(personId);
      return person === undefined ? [] : [{ ...person, score, evidence }];
    });
  },
});

// -------------------------------------------------------------------- ask

// How many people one ask loads by recency before the query itself has to
// choose. A personal network is hundreds of people (architecture stance), so
// this is a ceiling, not the expected size.
const ASK_NETWORK_LIMIT = 200;

// The most recent lines per person. A person with a hundred memories would
// otherwise crowd out everyone else in the prompt.
const ASK_MEMORIES_PER_PERSON = 12;

// How many people's memory lines one query reads. See listAskMemories: the
// embedding on every row, not the text, is what makes this need a bound.
const ASK_MEMORY_CHUNK = 25;

// Prompt budget for the network listing, in characters. Roughly 4 characters
// a token, so this is about 30k prompt tokens -- comfortably inside a single
// call and, at the plan's measured rates, a few cents an ask.
const MAX_DOSSIER_CHARS = 120_000;

// Matches beyond this are noise: the answer to "who do I know who does X" is
// a handful of people, not a page of them.
const MAX_ASK_MATCHES = 10;

// Bounds on what the client may send. Rejected rather than truncated: a
// client sending more than this is a bug or an abuse, and quietly trimming
// would hide both while still spending on the call.
const MAX_ASK_TEXT_LENGTH = 2000;
const MAX_ASK_HISTORY_TURNS = 20;
const ASK_TOO_LONG_ERROR = "Keep each message under 2000 characters";

const askTurnValidator = v.object({
  role: v.union(v.literal("user"), v.literal("assistant")),
  text: v.string(),
});

// What one person's card looks like to the ask prompt. Not personValidator:
// the model needs platform names, and has no use for photo urls or storage
// ids. The lines come from listAskMemories, which has to be its own query.
const askCardValidator = v.object({
  _id: v.id("people"),
  name: v.string(),
  headline: v.optional(v.string()),
  bio: v.optional(v.string()),
  role: v.optional(v.string()),
  company: v.optional(v.string()),
  cityName: v.optional(v.string()),
  platforms: v.array(v.string()),
});

type AskPerson = Infer<typeof askCardValidator> & {
  memories: Array<{ text: string; createdAt: number }>;
};

export const listNetworkForAsk = internalQuery({
  args: {
    userId: v.string(),
    // Given by the narrowing path, which has already chosen who is worth
    // sending. Absent means "the most recently touched people".
    personIds: v.optional(v.array(v.id("people"))),
  },
  returns: v.array(askCardValidator),
  handler: async (ctx, args) => {
    let people: Array<Doc<"people">>;
    if (args.personIds === undefined) {
      people = await ctx.db
        .query("people")
        .withIndex("by_user_and_updatedAt", (q) => q.eq("userId", args.userId))
        .order("desc")
        .take(ASK_NETWORK_LIMIT);
    } else {
      people = [];
      for (const id of args.personIds.slice(0, ASK_NETWORK_LIMIT)) {
        const person = await ctx.db.get("people", id);
        // The ids come from a userId-filtered vector search, so this can only
        // fail for a person deleted mid-ask -- but ownership is not a thing to
        // take on trust in the one place the whole card gets read out loud.
        if (person !== null && person.userId === args.userId) {
          people.push(person);
        }
      }
    }
    return people.map((person) => ({
      _id: person._id,
      name: person.name,
      headline: person.headline,
      bio: person.bio,
      role: person.role,
      company: person.company,
      cityName: person.city?.name,
      // The legacy platform scalar counts too: a person captured before
      // contactHandles existed is still reachable on that platform.
      platforms: [
        ...new Set(
          [
            person.platform,
            ...(person.contactHandles ?? []).map((handle) => handle.platform),
          ].filter(
            (part): part is string => part !== undefined && part.trim() !== "",
          ),
        ),
      ],
    }));
  },
});

// Memory lines for a handful of people at a time. Separate from the query
// above, and chunked by its caller, for one hard reason: a memory row carries
// a 1536-float embedding, about 12 KB, and Convex bounds a single query at
// 8 MiB of reads. The whole network's lines in one transaction is tens of
// megabytes and simply fails, however small the text itself is.
export const listAskMemories = internalQuery({
  args: { userId: v.string(), personIds: v.array(v.id("people")) },
  returns: v.array(
    v.object({
      personId: v.id("people"),
      text: v.string(),
      createdAt: v.number(),
    }),
  ),
  handler: async (ctx, args) => {
    const rows: Array<{
      personId: Id<"people">;
      text: string;
      createdAt: number;
    }> = [];
    for (const personId of args.personIds.slice(0, ASK_MEMORY_CHUNK)) {
      const recent = await ctx.db
        .query("memories")
        .withIndex("by_person", (q) => q.eq("personId", personId))
        .order("desc")
        .take(ASK_MEMORIES_PER_PERSON);
      // Oldest first, so the lines read as the timeline the user wrote.
      for (const memory of recent.reverse()) {
        if (memory.userId !== args.userId) {
          continue;
        }
        rows.push({
          personId,
          text: memory.text,
          createdAt: memory.createdAt,
        });
      }
    }
    return rows;
  },
});

// The people plus their lines, across as many bounded queries as it takes.
async function loadNetworkForAsk(
  ctx: ActionCtx,
  userId: string,
  personIds?: Array<Id<"people">>,
): Promise<AskPerson[]> {
  const cards: Array<Infer<typeof askCardValidator>> = await ctx.runQuery(
    internal.people.listNetworkForAsk,
    { userId, personIds },
  );
  const network: AskPerson[] = cards.map((card) => ({ ...card, memories: [] }));
  const byId = new Map(network.map((person) => [person._id, person]));
  for (let start = 0; start < network.length; start += ASK_MEMORY_CHUNK) {
    const chunk = network
      .slice(start, start + ASK_MEMORY_CHUNK)
      .map((person) => person._id);
    const rows: Array<{
      personId: Id<"people">;
      text: string;
      createdAt: number;
    }> = await ctx.runQuery(internal.people.listAskMemories, {
      userId,
      personIds: chunk,
    });
    for (const row of rows) {
      byId
        .get(row.personId)
        ?.memories.push({ text: row.text, createdAt: row.createdAt });
    }
  }
  return network;
}

// Ranked personIds for a query, best first. Deliberately without the
// MIN_SEMANTIC_SCORE floor semanticSearch applies: this picks WHICH dossiers
// to send, and a weakly-matching person is still a better use of the budget
// than one chosen by recency alone.
async function rankPeopleForAsk(
  ctx: ActionCtx,
  userId: string,
  query: string,
): Promise<Array<Id<"people">>> {
  const vector = await embedText(query);
  const [personHits, memoryHits] = await Promise.all([
    ctx.vectorSearch("people", "by_embedding", {
      vector,
      limit: ASK_NETWORK_LIMIT,
      filter: (q) => q.eq("userId", userId),
    }),
    ctx.vectorSearch("memories", "by_embedding", {
      vector,
      limit: ASK_NETWORK_LIMIT,
      filter: (q) => q.eq("userId", userId),
    }),
  ]);
  const best = new Map<Id<"people">, number>();
  const keepBest = (personId: Id<"people">, score: number) => {
    if (score > (best.get(personId) ?? -1)) {
      best.set(personId, score);
    }
  };
  for (const hit of personHits) {
    keepBest(hit._id, hit._score);
  }
  if (memoryHits.length > 0) {
    const scores = new Map(memoryHits.map((hit) => [hit._id, hit._score]));
    const owners: Array<{
      _id: Id<"memories">;
      personId: Id<"people">;
      text: string;
    }> = await ctx.runQuery(internal.memories.fetchMemoryOwners, {
      ids: memoryHits.map((hit) => hit._id),
    });
    for (const owner of owners) {
      keepBest(owner.personId, scores.get(owner._id) ?? 0);
    }
  }
  return [...best.entries()]
    .sort(([, a], [, b]) => b - a)
    .map(([personId]) => personId);
}

// Dossiers in order until the prompt budget runs out. refs[i] is who
// "#(i + 1)" means, so a ref the model answers with always names a person it
// was actually shown. A short return means people were left out.
function packDossiers(network: AskPerson[]): {
  refs: Array<Id<"people">>;
  dossiers: string[];
} {
  const refs: Array<Id<"people">> = [];
  const dossiers: string[] = [];
  let used = 0;
  for (const person of network) {
    const text = buildDossier(refs.length + 1, person);
    // The first person always goes in, however long: an ask over a network
    // of one must not come back empty because that one person is chatty.
    if (used + text.length > MAX_DOSSIER_CHARS && refs.length > 0) {
      break;
    }
    refs.push(person._id);
    dossiers.push(text);
    used += text.length + 2;
  }
  return { refs, dossiers };
}

// "Do I know anyone with database experience" over the whole network in one
// model call. Bridging is prompt-level, not infrastructure: a personal
// network is small enough to reason about whole, so there is no graph to
// build (architecture stance). The client holds the conversation; this call
// keeps no session state.
export const ask = action({
  args: {
    query: v.string(),
    // Prior turns, oldest first. The client owns them, so a refinement is
    // just another call with more context rather than a server-side session.
    history: v.optional(v.array(askTurnValidator)),
  },
  returns: v.object({
    // Carries who each match is, not just their id. The dossiers are already
    // in memory here, so naming them costs nothing -- where a client holding
    // only ids would have to read every matched person back one by one just
    // to render a list.
    matches: v.array(
      v.object({
        personId: v.id("people"),
        name: v.string(),
        company: v.optional(v.string()),
        role: v.optional(v.string()),
        cityName: v.optional(v.string()),
        kind: v.union(v.literal("direct"), v.literal("bridge")),
        why: v.string(),
      }),
    ),
    // Set instead of guessing when the request is too vague to answer.
    clarifyingQuestion: v.union(v.null(), v.string()),
  }),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    // Two windows, both before any work: an ask costs roughly a hundred times
    // what a semantic search does, so the burst limit alone would not bound
    // a day's spend.
    await ctx.runMutation(internal.people.enforceRateLimit, {
      userId,
      action: "ask:minute",
      max: 10,
      windowMs: MINUTE_MS,
    });
    await ctx.runMutation(internal.people.enforceRateLimit, {
      userId,
      action: "ask:day",
      max: 100,
      windowMs: DAY_MS,
    });

    const query = args.query.trim();
    if (query === "") {
      throw new Error("Ask a question first");
    }
    const history = args.history ?? [];
    if (history.length > MAX_ASK_HISTORY_TURNS) {
      throw new Error("This conversation is too long -- start a new one");
    }
    if (
      query.length > MAX_ASK_TEXT_LENGTH ||
      history.some((turn) => turn.text.length > MAX_ASK_TEXT_LENGTH)
    ) {
      throw new Error(ASK_TOO_LONG_ERROR);
    }

    let network = await loadNetworkForAsk(ctx, userId);
    let packed = packDossiers(network);
    // A network that hit the load cap, or one the budget had to cut short,
    // has its candidates chosen by the question instead of by recency.
    // Embedding retrieval earns its keep here and nowhere else in this flow.
    if (
      network.length === ASK_NETWORK_LIMIT ||
      packed.refs.length < network.length
    ) {
      const ranked = await rankPeopleForAsk(ctx, userId, query);
      if (ranked.length > 0) {
        network = await loadNetworkForAsk(ctx, userId, ranked);
        packed = packDossiers(network);
      }
    }

    const { refs, dossiers } = packed;
    if (refs.length === 0) {
      // Nobody saved yet: an empty prompt cannot answer anything, and paying
      // a model to say so is waste.
      return { matches: [], clarifyingQuestion: null };
    }

    const answer = await askNetwork(query, dossiers.join("\n\n"), history);
    const seen = new Set<number>();
    const matches: Array<{
      personId: Id<"people">;
      name: string;
      company?: string;
      role?: string;
      cityName?: string;
      kind: "direct" | "bridge";
      why: string;
    }> = [];
    for (const match of answer.matches) {
      const personId = refs[match.ref - 1];
      // refs is built by walking `network` in order, so a ref indexes the same
      // person in both.
      const shown = network[match.ref - 1];
      // A ref nobody was shown, a repeat, or a kind outside the schema all
      // mean the model went off contract. Drop the match rather than answer
      // with a person the user never saved.
      if (
        personId === undefined ||
        shown === undefined ||
        seen.has(match.ref) ||
        (match.kind !== "direct" && match.kind !== "bridge") ||
        typeof match.why !== "string"
      ) {
        continue;
      }
      seen.add(match.ref);
      matches.push({
        personId,
        name: shown.name,
        company: shown.company,
        role: shown.role,
        cityName: shown.cityName,
        kind: match.kind,
        why: match.why,
      });
      if (matches.length === MAX_ASK_MATCHES) {
        break;
      }
    }
    return { matches, clarifyingQuestion: answer.clarifyingQuestion ?? null };
  },
});

// One-off maintenance: schedule embeddings for people created before the
// semantic search feature. Run with: npx convex run people:backfillEmbeddings
export const listMissingEmbeddings = internalQuery({
  args: {},
  returns: v.array(v.id("people")),
  handler: async (ctx) => {
    const people = await ctx.db.query("people").take(200);
    return people
      .filter((person) => person.embedding === undefined)
      .map((person) => person._id);
  },
});

export const backfillEmbeddings = internalAction({
  args: {},
  returns: v.number(),
  handler: async (ctx) => {
    const ids: Array<Id<"people">> = await ctx.runQuery(
      internal.people.listMissingEmbeddings,
      {},
    );
    let embedded = 0;
    for (const personId of ids) {
      // One bad row must not abort the sweep: this runs unattended from the
      // daily cron, and an aborted loop would re-fail identically every day
      // while everyone behind the bad row stays unembedded.
      try {
        await embedPerson(ctx, personId);
        embedded++;
      } catch (error) {
        console.error(`backfillEmbeddings: skipping ${personId}`, error);
      }
    }
    return embedded;
  },
});

// One-off maintenance: rows written before searchText existed are invisible
// to keyword search until patched. Run once after deploy with:
// npx convex run people:backfillSearchText
export const backfillSearchText = internalMutation({
  args: {},
  returns: v.number(),
  handler: async (ctx) => {
    const candidates = await ctx.db.query("people").take(BACKFILL_BATCH_SIZE);
    const missing = candidates.filter(
      (person) => person.searchText === undefined,
    );
    for (const person of missing) {
      await ctx.db.patch("people", person._id, {
        searchText: personSearchText(person),
      });
    }
    return missing.length;
  },
});

// Idempotency key for the maintenance functions below: re-running one must
// never double-index a handle. JSON so a platform containing a separator
// cannot collide with another pair.
const handleIndexKey = (row: { platform: string; valueKey: string }) =>
  JSON.stringify([row.platform, row.valueKey]);

// One-off maintenance: people saved between contactHandles shipping and the
// personHandles index existing carry the array but no index rows, so a share
// of a handle they already hold would twin them. Paged rather than a single
// batch, because an unindexed person is a corrupted identity, not just a
// missing search hit -- "done" has to mean it. Run with:
// npx convex run people:backfillPersonHandles '{}'
// and re-run with '{"cursor": "<cursor>"}' until isDone.
export const backfillPersonHandles = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())) },
  returns: v.object({
    patched: v.number(),
    // A digitless phone/whatsapp entry (identity brief, W1): sibling to
    // backfillLegacyHandles's own gate below, for the same reason -- this
    // migration indexes contactHandles entries that already exist but have
    // no personHandles row yet, and indexing one straight through would
    // fold it onto the same collision-prone key hasPhoneDigit gates on
    // every live write path.
    refused: v.number(),
    isDone: v.boolean(),
    cursor: v.string(),
  }),
  handler: async (ctx, args) => {
    const page = await ctx.db.query("people").paginate({
      numItems: BACKFILL_BATCH_SIZE,
      cursor: args.cursor ?? null,
    });
    let patched = 0;
    let refused = 0;
    for (const person of page.page) {
      const handles = person.contactHandles ?? [];
      if (handles.length === 0) {
        continue;
      }
      const existing = await ctx.db
        .query("personHandles")
        .withIndex("by_person", (q) => q.eq("personId", person._id))
        .take(MAX_CONTACT_HANDLES);
      const indexed = new Set(existing.map(handleIndexKey));
      const missing = handles.filter(
        (handle) => !indexed.has(handleIndexKey(handleIndexKeys(handle))),
      );
      if (missing.length === 0) {
        continue;
      }
      const indexable = missing.filter((handle) => {
        const keys = handleIndexKeys(handle);
        if (isPhoneNumberPlatform(keys.platform) && !hasPhoneDigit(handle.value)) {
          refused++;
          return false;
        }
        return true;
      });
      if (indexable.length === 0) {
        continue;
      }
      await insertPersonHandles(ctx, person.userId, person._id, indexable);
      patched++;
    }
    return { patched, refused, isDone: page.isDone, cursor: page.continueCursor };
  },
});

// One-off maintenance: the screenshot and meet-exchange paths wrote people
// with only the legacy platform/handle scalars, so those accounts were
// invisible to every handle lookup and a later share twinned the person.
// This folds those scalars into contactHandles and the personHandles index.
// Paged for the same reason backfillPersonHandles is: an unindexed person is
// a corrupted identity, so "done" has to mean it. Run with:
// npx convex run people:backfillLegacyHandles '{}'
// and re-run with '{"cursor": "<cursor>"}' until isDone.
//
// Deliberately conservative on two counts. A person whose array already
// holds that platform is skipped and counted, never overwritten: which of
// two disagreeing accounts is current is a product decision, not a
// migration's. And neither updatedAt nor searchText is touched, because a
// migration is not an edit -- recency ordering stays where the user left it,
// and the legacy handle is already in the keyword haystack.
export const backfillLegacyHandles = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())) },
  returns: v.object({
    patched: v.number(),
    skipped: v.number(),
    // A digitless phone/whatsapp scalar (identity brief, X2): folded here
    // with no gate, this would recreate the exact collision hasPhoneDigit
    // exists to prevent, just through the maintenance path instead of a
    // live write. Counted separately from "skipped" (a disagreement this
    // migration correctly declines to referee) since a refused row is a
    // different situation -- there is nothing here worth indexing at all.
    refused: v.number(),
    isDone: v.boolean(),
    cursor: v.string(),
  }),
  handler: async (ctx, args) => {
    const page = await ctx.db.query("people").paginate({
      numItems: BACKFILL_BATCH_SIZE,
      cursor: args.cursor ?? null,
    });
    let patched = 0;
    let skipped = 0;
    let refused = 0;
    for (const person of page.page) {
      if (person.platform === undefined || person.handle === undefined) {
        continue;
      }
      const legacy = {
        platform: person.platform,
        value: handleDisplayValue(person.handle),
      };
      const keys = handleIndexKeys(legacy);
      // A platform with no handle, or a handle of punctuation alone, names
      // no account: there is nothing to index and nothing to report.
      if (keys.platform === "" || keys.valueKey === "") {
        continue;
      }
      // Same refusal as every other write path (convex/handleKeys.ts's
      // hasPhoneDigit): a digitless phone/whatsapp value folds to a plain
      // lowercase string, and two different unreadable legacy rows could
      // otherwise collide on the same personHandles row the moment this
      // migration ran.
      if (isPhoneNumberPlatform(keys.platform) && !hasPhoneDigit(legacy.value)) {
        refused++;
        continue;
      }
      const handles = person.contactHandles ?? [];
      if (
        handles.length >= MAX_CONTACT_HANDLES ||
        handles.some(
          (handle) => handleIndexKeys(handle).platform === keys.platform,
        )
      ) {
        skipped++;
        continue;
      }
      // Same idempotency rule as backfillPersonHandles: an index row that
      // already exists is never doubled, however the two got out of step.
      const existing = await ctx.db
        .query("personHandles")
        .withIndex("by_person", (q) => q.eq("personId", person._id))
        .take(MAX_CONTACT_HANDLES);
      const indexed = new Set(existing.map(handleIndexKey));
      await ctx.db.patch("people", person._id, {
        contactHandles: [
          ...handles,
          { platform: keys.platform, value: legacy.value },
        ],
      });
      if (!indexed.has(handleIndexKey(keys))) {
        await insertPersonHandles(ctx, person.userId, person._id, [legacy]);
      }
      patched++;
    }
    return {
      patched,
      skipped,
      refused,
      isDone: page.isDone,
      cursor: page.continueCursor,
    };
  },
});

// One-off maintenance: personHandles rows for phone and whatsapp were folded
// by the old trim+lowercase key, which reads "(415) 555-0123" and
// "+1 415 555 0123" as two different accounts. This recomputes valueKey with
// handleValueKey's phone-aware fold, reading the source number back from
// contactHandles rather than the row itself -- the old key is lossy (digits
// alone cannot be un-stripped into an E.164 string), so contactHandles.value
// is the only place the original number still lives. Two people who saved
// the same number in different shapes can land on one key after this; that
// is a duplicate for reportDuplicateHandleOwners to surface, not this
// migration's to merge, same doctrine as it. Paged like the neighbors above.
// Run with:
// npx convex run people:backfillPhoneHandleKeys '{}'
// and re-run with '{"cursor": "<cursor>"}' until isDone.
export const backfillPhoneHandleKeys = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())) },
  returns: v.object({
    patched: v.number(),
    isDone: v.boolean(),
    cursor: v.string(),
  }),
  handler: async (ctx, args) => {
    const page = await ctx.db.query("people").paginate({
      numItems: BACKFILL_BATCH_SIZE,
      cursor: args.cursor ?? null,
    });
    let patched = 0;
    for (const person of page.page) {
      const handles = person.contactHandles ?? [];
      if (handles.length === 0) {
        continue;
      }
      const rows = await ctx.db
        .query("personHandles")
        .withIndex("by_person", (q) => q.eq("personId", person._id))
        .take(MAX_CONTACT_HANDLES);
      for (const row of rows) {
        if (row.platform !== "phone" && row.platform !== "whatsapp") {
          continue;
        }
        const source = handles.find(
          (handle) => handleIndexKeys(handle).platform === row.platform,
        );
        if (source === undefined) {
          continue;
        }
        const newKey = handleValueKey(source.value, row.platform);
        if (newKey !== row.valueKey) {
          await ctx.db.patch("personHandles", row._id, { valueKey: newKey });
          patched++;
        }
      }
    }
    return { patched, isDone: page.isDone, cursor: page.continueCursor };
  },
});

// How many index rows one report page scans. MAX_HANDLE_OWNERS, how many
// owners of a single account it will name, is declared with findHandleOwner
// above, which uses the same cap for the same reason.
const DUPLICATE_SCAN_PAGE_SIZE = 500;

// Report only, never a merge: which of two people holding one account is the
// real one is a product decision, and a migration that guessed would delete
// somebody's memory of a person. This exists so the wave C reconciliation is
// decided on real numbers -- and only a report of zero duplicates lets
// saveSharedProfile's lookup move from .first() to .unique(). Run with:
// npx convex run people:reportDuplicateHandleOwners '{}'
// and re-run with '{"cursor": "<cursor>"}' until isDone.
export const reportDuplicateHandleOwners = internalQuery({
  // pageSize is for tests, which prove the page-boundary rule below with a
  // tiny page.
  args: {
    cursor: v.optional(v.union(v.string(), v.null())),
    pageSize: v.optional(v.number()),
  },
  returns: v.object({
    duplicates: v.array(
      v.object({
        userId: v.string(),
        platform: v.string(),
        valueKey: v.string(),
        personIds: v.array(v.id("people")),
      }),
    ),
    scanned: v.number(),
    isDone: v.boolean(),
    cursor: v.string(),
  }),
  handler: async (ctx, args) => {
    // Paged over the identity index rather than the table's creation order,
    // so every row of one (userId, platform, valueKey) is adjacent and a
    // page's interior groups are complete as read.
    const page = await ctx.db
      .query("personHandles")
      .withIndex("by_user_and_platform_and_valueKey")
      .paginate({
        numItems: args.pageSize ?? DUPLICATE_SCAN_PAGE_SIZE,
        cursor: args.cursor ?? null,
      });

    const groups = new Map<string, Array<Doc<"personHandles">>>();
    for (const row of page.page) {
      const key = JSON.stringify([row.userId, row.platform, row.valueKey]);
      const rows = groups.get(key);
      if (rows === undefined) {
        groups.set(key, [row]);
      } else {
        rows.push(row);
      }
    }
    const keys = [...groups.keys()];
    const pageRowIds = new Set(page.page.map((row) => row._id));
    const duplicates: Array<{
      userId: string;
      platform: string;
      valueKey: string;
      personIds: Array<Id<"people">>;
    }> = [];
    for (const [position, key] of keys.entries()) {
      const inPage = groups.get(key) ?? [];
      const sample = inPage[0];
      // Only the first and last group of a page can continue outside it, so
      // only those two need the index consulted. Two extra reads per page
      // buy an exact report; grouping page-locally would miss a split group
      // entirely and report zero duplicates where there are some.
      const rows =
        position === 0 || position === keys.length - 1
          ? await ctx.db
              .query("personHandles")
              .withIndex("by_user_and_platform_and_valueKey", (q) =>
                q
                  .eq("userId", sample.userId)
                  .eq("platform", sample.platform)
                  .eq("valueKey", sample.valueKey),
              )
              .take(MAX_HANDLE_OWNERS)
          : inPage;
      // The page holding a group's first row owns reporting it, so a split
      // group is counted once rather than once per page it touches.
      if (!pageRowIds.has(rows[0]._id)) {
        continue;
      }
      // By person, not by row: one person can hold two index rows for their
      // own account (saveSharedProfile's attach path inserts unconditionally),
      // and that is drift to heal, not two people to reconcile.
      const personIds = [...new Set(rows.map((row) => row.personId))];
      if (personIds.length > 1) {
        duplicates.push({
          userId: sample.userId,
          platform: sample.platform,
          valueKey: sample.valueKey,
          personIds,
        });
      }
    }
    return {
      duplicates,
      scanned: page.page.length,
      isDone: page.isDone,
      cursor: page.continueCursor,
    };
  },
});

// One-off maintenance: rows written before normalizedName existed (or
// inserted directly by the capture pipeline, which bypasses addPerson)
// are unreachable by search_normalized_name until patched. Run with:
// npx convex run people:backfillNormalizedNames
export const backfillNormalizedNames = internalMutation({
  args: {},
  returns: v.number(),
  handler: async (ctx) => {
    const candidates = await ctx.db.query("people").take(BACKFILL_BATCH_SIZE);
    const missing = candidates.filter(
      (person) => person.normalizedName === undefined,
    );
    for (const person of missing) {
      await ctx.db.patch("people", person._id, {
        normalizedName: normalizeName(person.name),
      });
    }
    return missing.length;
  },
});
