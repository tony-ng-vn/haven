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
import { buildEmbedText } from "../src/lib";
import { embedText } from "./openaiClient";
import { requireUser } from "./authz";
import { checkRateLimit } from "./rateLimit";
import { normalizeName, personSearchText } from "./nameSearch";
import { cityInputValidator } from "./profileFields";
import { contactHandleValidator } from "./peopleFields";
import {
  handleDisplayValue,
  handleIndexKeys,
  handleValueKey,
} from "./handleKeys";
import { requireImageBlob } from "./imageBlobs";
import { deleteMemories, syncMemories } from "./memories";

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
  updatedAt: v.number(),
});

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
    fields.company = company;
    fields.companyKey = normalizeName(company);
  }
  if (args.role !== undefined) {
    const role = args.role.trim();
    if (role === "") {
      throw new Error("Role cannot be blank");
    }
    fields.role = role;
    fields.roleKey = normalizeName(role);
  }
  if (args.city !== undefined) {
    const name = args.city.name.trim();
    if (name === "") {
      throw new Error("City cannot be blank");
    }
    fields.city = { ...args.city, name };
    fields.cityKey = normalizeName(name);
  }
  return fields;
}

type ContactHandleInput = Infer<typeof contactHandleValidator>;

const MAX_CONTACT_HANDLES = 8;

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
    if (seen.has(platform)) {
      throw new Error("Keep one handle per platform");
    }
    seen.add(platform);
    return { platform, value };
  });
}

async function insertPersonHandles(
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
async function deletePersonHandles(
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

// A re-share must never discard what the user typed, so a new note joins the
// person's context instead of replacing it. Clamped rather than refused at
// the cap: the drain replays a queued note long after the sheet closed, so
// an overflow cannot ask the user and must not strand the capture. The
// caller is told when the cap cut the note, so a drain never mistakes a
// clipped save for a complete one.
function appendContext(
  existing: string | undefined,
  note: string | undefined,
): { context: string | undefined; noteTruncated: boolean } {
  if (note === undefined) {
    return { context: existing, noteTruncated: false };
  }
  const next =
    existing === undefined || existing === "" ? note : `${existing}\n${note}`;
  const context = next.slice(0, MAX_CONTEXT_LENGTH);
  return { context, noteTruncated: context.length < next.length };
}

// The shared URL is the only pointer back to the profile -- a LinkedIn slug
// cannot be rebuilt into one -- so a person without a link keeps it. An
// existing link is never overwritten: the user chose that one.
function linkBackfill(
  person: Doc<"people">,
  profileUrl: string,
): { link?: string } {
  if (profileUrl === "" || (person.link !== undefined && person.link !== "")) {
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
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "addPerson", 30, MINUTE_MS);
    const name = args.name.trim();
    if (name === "") {
      throw new Error("Name is required");
    }
    // Identity and a story are what make a manual add searchable and
    // referenceable later, so a handle and a note are required here; the
    // capture paths stay lenient because they run without the user present.
    const contactHandles = validateContactHandles(args.contactHandles ?? []);
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
    const attributes = structuredAttributeFields(args);
    const now = Date.now();
    const personId = await ctx.db.insert("people", {
      userId,
      name,
      normalizedName: normalizeName(name),
      context: args.context,
      contactHandles,
      preferredPlatform,
      photoStorageId: args.photoStorageId,
      ...attributes,
      searchText: personSearchText({
        name,
        company: attributes.company,
        role: attributes.role,
        city: attributes.city,
        contactHandles,
        context: args.context,
      }),
      updatedAt: now,
    });
    // Same transaction as the array, always: the index is only trustworthy
    // if it cannot drift from what the card shows.
    await insertPersonHandles(ctx, userId, personId, contactHandles);
    await syncMemories(ctx, {
      userId,
      personId,
      context: args.context,
      createdAt: now,
    });
    await ctx.scheduler.runAfter(0, internal.people.embed, { personId });
    return personId;
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

export const getPerson = query({
  args: { id: v.id("people") },
  returns: v.union(v.null(), personValidator),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    const person = await ctx.db.get("people", args.id);
    if (person === null || person.userId !== userId) {
      return null;
    }
    return await projectPerson(ctx, person);
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
  returns: personValidator,
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
      fields.contactHandles = validateContactHandles(args.contactHandles);
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
  },
  returns: v.object({
    status: v.union(
      v.literal("created"),
      v.literal("already"),
      v.literal("attached"),
    ),
    personId: v.id("people"),
    // True when the context cap cut the note: the capture landed, but the
    // drain should surface the loss instead of reporting a complete save.
    noteTruncated: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "saveSharedProfile", 30, MINUTE_MS);

    // The stored value carries the same shape as its identity key: a share of
    // "@mai.makes" and one of "mai.makes" must render and search alike, not
    // just dedup alike. validateContactHandles owns the platform fold and the
    // blank checks, same as every other handle write path.
    const [{ platform, value }] = validateContactHandles([
      { platform: args.platform, value: handleDisplayValue(args.handleValue) },
    ]);
    const valueKey = handleValueKey(value);
    const name = args.name.trim();
    if (name === "") {
      throw new Error("Name is required");
    }
    const trimmedNote = args.note?.trim();
    const note =
      trimmedNote === undefined || trimmedNote === "" ? undefined : trimmedNote;
    const profileUrl = args.profileUrl.trim();

    const indexed = await ctx.db
      .query("personHandles")
      .withIndex("by_user_and_platform_and_valueKey", (q) =>
        q
          .eq("userId", userId)
          .eq("platform", platform)
          .eq("valueKey", valueKey),
      )
      .first();
    const owner =
      indexed === null ? null : await ctx.db.get("people", indexed.personId);
    if (indexed !== null && owner === null) {
      // Self-heal a row orphaned by a write that bypassed deletePerson,
      // rather than let it shadow the person this capture is about.
      await ctx.db.delete("personHandles", indexed._id);
    }
    if (owner !== null) {
      // Handle identity beats the attach target: this account provably
      // belongs to this person, however stale the caller's mirror is.
      const fields: Partial<Doc<"people">> = {};
      const { context, noteTruncated } = appendContext(owner.context, note);
      if (context !== owner.context) {
        fields.context = context;
      }
      Object.assign(fields, linkBackfill(owner, profileUrl));
      if (Object.keys(fields).length > 0) {
        const now = Date.now();
        await ctx.db.patch("people", owner._id, {
          ...fields,
          searchText: personSearchText({ ...owner, ...fields }),
          updatedAt: now,
        });
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
      return { status: "already" as const, personId: owner._id, noteTruncated };
    }

    if (args.attachToPersonId !== undefined) {
      const target = await ctx.db.get("people", args.attachToPersonId);
      // A target that is gone or somebody else's falls through to create:
      // the extension's mirror can be days stale and a capture is never lost.
      if (target !== null && target.userId === userId) {
        const handles = target.contactHandles ?? [];
        // Folded on both sides, like validateContactHandles does: a legacy row
        // holding "Instagram " is the same platform, and mistaking it for a
        // second one would throw away the note over an identical handle.
        const held = handles.find(
          (handle) => handleIndexKeys(handle).platform === platform,
        );
        // A target already holding a different account on this platform means
        // the mirror was stale. The drain replays this with nobody present to
        // resolve it, so the capture falls through to create rather than
        // strand the queued item; the user can merge the twins later.
        if (held === undefined || handleIndexKeys(held).valueKey === valueKey) {
          const { context, noteTruncated } = appendContext(
            target.context,
            note,
          );
          const fields: Partial<Doc<"people">> = {
            context,
            ...linkBackfill(target, profileUrl),
          };
          if (held === undefined) {
            fields.contactHandles = validateContactHandles([
              ...handles,
              { platform, value },
            ]);
          }
          const now = Date.now();
          await ctx.db.patch("people", target._id, {
            ...fields,
            searchText: personSearchText({ ...target, ...fields }),
            updatedAt: now,
          });
          // Inserted even when the array already held this handle: that only
          // happens for a person written before this index existed.
          await insertPersonHandles(ctx, userId, target._id, [
            { platform, value },
          ]);
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
          };
        }
      }
    }

    const contactHandles = [{ platform, value }];
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
    return { status: "created" as const, personId, noteTruncated };
  },
});

// ------------------------------------------------------------- embeddings

export const getPersonInternal = internalQuery({
  args: { id: v.id("people") },
  handler: async (ctx, args) => {
    return await ctx.db.get("people", args.id);
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
      await insertPersonHandles(ctx, person.userId, person._id, missing);
      patched++;
    }
    return { patched, isDone: page.isDone, cursor: page.continueCursor };
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
      isDone: page.isDone,
      cursor: page.continueCursor,
    };
  },
});

// How many index rows one report page scans, and how many owners of a single
// account it will name. A handle owned by more people than the cap is already
// a five-alarm finding; the cap only stops one pathological group from
// unbounding the read.
const DUPLICATE_SCAN_PAGE_SIZE = 500;
const MAX_HANDLE_OWNERS = 64;

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
