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
import { requireImageBlob } from "./imageBlobs";

// Bound every list read so the query stays scalable as the table grows.
const RESULT_LIMIT = 20;

// Semantic matches below this cosine similarity read as noise, not memory.
// Tuned against real data during verification.
const MIN_SEMANTIC_SCORE = 0.3;

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

// The identity key behind a handle: the same account shared as "@Mai.Makes"
// and as "mai.makes" has to resolve to one person. Deliberately naive in v1;
// per-platform rules can grow here later.
function handleValueKey(value: string): string {
  return value.trim().replace(/^@+/, "").toLowerCase();
}

// The personHandles shape for one contactHandles entry. Legacy rows can hold
// an unnormalized platform, so the index row folds it the same way
// validateContactHandles does rather than trusting what is stored.
function handleIndexKeys(handle: ContactHandleInput): {
  platform: string;
  valueKey: string;
} {
  return {
    platform: handle.platform.trim().toLowerCase(),
    valueKey: handleValueKey(handle.value),
  };
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
// person's context instead of replacing it.
function appendContext(
  existing: string | undefined,
  note: string | undefined,
): string | undefined {
  if (note === undefined) {
    return existing;
  }
  const next =
    existing === undefined || existing === "" ? note : `${existing}\n${note}`;
  if (next.length > MAX_CONTEXT_LENGTH) {
    throw new Error(CONTEXT_TOO_LONG_ERROR);
  }
  return next;
}

// The shared URL is the only pointer back to the profile -- a LinkedIn slug
// cannot be rebuilt into one -- so a person without a link keeps it. An
// existing link is never overwritten: the user chose that one.
function linkFields(
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
    if (args.context !== undefined && args.context.length > MAX_CONTEXT_LENGTH) {
      throw new Error(CONTEXT_TOO_LONG_ERROR);
    }
    if (args.photoStorageId !== undefined) {
      await requireImageBlob(ctx, args.photoStorageId, PHOTO_ERROR);
    }
    const contactHandles =
      args.contactHandles === undefined
        ? undefined
        : validateContactHandles(args.contactHandles);
    const preferredPlatform =
      args.preferredPlatform === undefined
        ? undefined
        : validatePreferredPlatform(args.preferredPlatform, contactHandles ?? []);
    const attributes = structuredAttributeFields(args);
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
      updatedAt: Date.now(),
    });
    // Same transaction as the array, always: the index is only trustworthy
    // if it cannot drift from what the card shows.
    await insertPersonHandles(ctx, userId, personId, contactHandles ?? []);
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
    await ctx.db.patch("people", args.id, {
      link: args.link,
      context: args.context,
      searchText: personSearchText({ ...person, context: args.context }),
      updatedAt: Date.now(),
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

    await ctx.db.patch("people", args.id, { ...fields, updatedAt: Date.now() });
    // A replaced array is rewritten wholesale rather than diffed: the list is
    // capped at 8, so a full rewrite is the same cost and cannot mis-diff.
    if (fields.contactHandles !== undefined) {
      await deletePersonHandles(ctx, args.id);
      await insertPersonHandles(ctx, userId, args.id, fields.contactHandles);
    }
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
    // lookup, so they go with the person.
    await deletePersonHandles(ctx, args.personId);
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
  }),
  handler: async (ctx, args) => {
    const userId = await requireUser(ctx);
    await checkRateLimit(ctx, userId, "saveSharedProfile", 30, MINUTE_MS);

    const platform = args.platform.trim().toLowerCase();
    if (platform === "") {
      throw new Error("A platform cannot be blank");
    }
    // The stored value carries the same shape as its identity key: a share of
    // "@mai.makes" and one of "mai.makes" must render and search alike, not
    // just dedup alike.
    const value = args.handleValue.trim().replace(/^@+/, "");
    const valueKey = handleValueKey(value);
    if (valueKey === "") {
      throw new Error("A handle cannot be blank");
    }
    const name = args.name.trim();
    if (name === "") {
      throw new Error("Name is required");
    }
    const trimmedNote = args.note?.trim();
    const note =
      trimmedNote === undefined || trimmedNote === "" ? undefined : trimmedNote;
    if (note !== undefined && note.length > MAX_CONTEXT_LENGTH) {
      throw new Error(CONTEXT_TOO_LONG_ERROR);
    }
    const profileUrl = args.profileUrl.trim();

    const indexed = await ctx.db
      .query("personHandles")
      .withIndex("by_user_platform_value", (q) =>
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
      const context = appendContext(owner.context, note);
      if (context !== owner.context) {
        fields.context = context;
      }
      Object.assign(fields, linkFields(owner, profileUrl));
      if (Object.keys(fields).length > 0) {
        await ctx.db.patch("people", owner._id, {
          ...fields,
          searchText: personSearchText({ ...owner, ...fields }),
          updatedAt: Date.now(),
        });
        await ctx.scheduler.runAfter(0, internal.people.embed, {
          personId: owner._id,
        });
      }
      return { status: "already" as const, personId: owner._id };
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
        if (held !== undefined && handleIndexKeys(held).valueKey !== valueKey) {
          // Ambiguous identity is refused; the sheet sends the user to the
          // person editor instead of guessing which account is current.
          throw new Error("Keep one handle per platform");
        }
        const fields: Partial<Doc<"people">> = {
          context: appendContext(target.context, note),
          ...linkFields(target, profileUrl),
        };
        if (held === undefined) {
          fields.contactHandles = validateContactHandles([
            ...handles,
            { platform, value },
          ]);
        }
        await ctx.db.patch("people", target._id, {
          ...fields,
          searchText: personSearchText({ ...target, ...fields }),
          updatedAt: Date.now(),
        });
        // Inserted even when the array already held this handle: that only
        // happens for a person written before this index existed.
        await insertPersonHandles(ctx, userId, target._id, [
          { platform, value },
        ]);
        await ctx.scheduler.runAfter(0, internal.people.embed, {
          personId: target._id,
        });
        return { status: "attached" as const, personId: target._id };
      }
    }

    const contactHandles = [{ platform, value }];
    const personId = await ctx.db.insert("people", {
      userId,
      name,
      normalizedName: normalizeName(name),
      context: note,
      link: profileUrl === "" ? undefined : profileUrl,
      contactHandles,
      // preferredPlatform stays unset: the share sheet never asks how the
      // user wants to reach this person.
      searchText: personSearchText({ name, contactHandles, context: note }),
      updatedAt: Date.now(),
    });
    await insertPersonHandles(ctx, userId, personId, contactHandles);
    await ctx.scheduler.runAfter(0, internal.people.embed, { personId });
    return { status: "created" as const, personId };
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
  score: v.number(),
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
    const matches = await ctx.vectorSearch("people", "by_embedding", {
      vector,
      limit: 8,
      filter: (q) => q.eq("userId", userId),
    });
    const strong = matches.filter((m) => m._score >= MIN_SEMANTIC_SCORE);
    if (strong.length === 0) {
      return [];
    }
    const scores = new Map(strong.map((m) => [m._id, m._score]));
    const people: Array<{
      _id: Id<"people">;
      _creationTime: number;
      name: string;
      link?: string;
      context?: string;
      platform?: string;
      handle?: string;
      headline?: string;
    }> = await ctx.runQuery(internal.people.fetchSearchResults, {
      ids: strong.map((m) => m._id),
    });
    return people
      .map((person) => ({ ...person, score: scores.get(person._id) ?? 0 }))
      .sort((a, b) => b.score - a.score);
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
      // Idempotent: re-running must never double-index a handle. The key
      // is JSON so a platform containing a separator cannot collide.
      const indexKey = (row: { platform: string; valueKey: string }) =>
        JSON.stringify([row.platform, row.valueKey]);
      const indexed = new Set(existing.map(indexKey));
      const missing = handles.filter(
        (handle) => !indexed.has(indexKey(handleIndexKeys(handle))),
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
