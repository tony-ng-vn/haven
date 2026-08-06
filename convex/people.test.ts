/// <reference types="vite/client" />
import { convexTest, type TestConvexForDataModel } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type {
  DataModelFromSchemaDefinition,
  FunctionArgs,
  FunctionReturnType,
} from "convex/server";
import { api, internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import schema from "./schema";
import { normalizeName } from "./nameSearch";
import { appendContext } from "./people";

const modules = import.meta.glob("./**/*.ts");

type TestDataModel = DataModelFromSchemaDefinition<typeof schema>;

// Mint a fake Clerk identity and return an authenticated test context bound
// to it. requireUser() keys ownership on tokenIdentifier ("issuer|subject"),
// which is what convex-test's withIdentity() synthesizes here.
let nextSubject = 0;
function asNewUser(t: ReturnType<typeof convexTest>) {
  const subject = `user_${nextSubject++}`;
  const issuer = "https://test.clerk.accounts.dev";
  const userId = `${issuer}|${subject}`;
  return { userId, as: t.withIdentity({ subject, issuer }) };
}

// addPerson now returns a creation outcome, not a bare id (identity brief,
// task 2): most of this file's calls exist only to seed a person and go on
// to test something else, so this unwraps the common case and throws loudly
// if a seed unexpectedly collides with an existing handle instead of
// creating -- which is exactly how the manualAdd collisions below would have
// surfaced, as confusing downstream assertions, without it.
async function addPersonId(
  as: TestConvexForDataModel<TestDataModel>,
  args: FunctionArgs<typeof api.people.addPersonWithOutcome>,
): Promise<Id<"people">> {
  const result = await as.mutation(api.people.addPersonWithOutcome, args);
  if (result.status !== "created") {
    throw new Error(`addPersonId: expected created, got ${result.status}`);
  }
  return result.personId;
}

// Strips provenance (source, platformId, addedAt) so tests about handle
// mechanics -- attaching, merging, migrating -- can keep asserting on
// platform and value alone, the way they did before those fields existed.
// Tests about provenance itself compare the full shape directly instead of
// going through this.
function displayOnly(
  handles: Array<{ platform: string; value: string }> | undefined,
): Array<{ platform: string; value: string }> | undefined {
  return handles?.map(({ platform, value }) => ({ platform, value }));
}

// editPerson now returns a handle_taken outcome alongside the edited person
// (identity brief, task 2), so a caller that just wants to assert on the
// saved fields needs to narrow past that first. Tests exercising handle_taken
// itself call editPerson directly instead of through this helper.
type EditPersonResult = FunctionReturnType<typeof api.people.editPerson>;
type EditedPerson = Exclude<EditPersonResult, { status: "handle_taken" }>;

async function editPersonOk(
  as: TestConvexForDataModel<TestDataModel>,
  args: FunctionArgs<typeof api.people.editPerson>,
): Promise<EditedPerson> {
  const result = await as.mutation(api.people.editPerson, args);
  if ("status" in result) {
    throw new Error(
      `editPersonOk: expected the edited person, got ${result.status}`,
    );
  }
  return result;
}

// Stub only the embeddings endpoint; anything else falls through to the
// real fetch. Scoped narrowly since most tests here never run the scheduled
// embed action at all (they don't call finishAllScheduledFunctions).
function stubEmbeddings(vector: number[]) {
  const realFetch = globalThis.fetch;
  vi.stubGlobal(
    "fetch",
    async (input: RequestInfo | URL, init?: RequestInit) => {
      const raw = String(input);
      let url: URL;
      try {
        url = new URL(raw);
      } catch {
        return realFetch(input, init);
      }
      if (url.hostname === "api.openai.com" && url.pathname.includes("/embeddings")) {
        return Response.json({ data: [{ embedding: vector }] });
      }
      return realFetch(input, init);
    },
  );
}

// Like stubEmbeddings, but each call to the embeddings endpoint is handed
// to `respond`, which decides success or failure per call -- for exercising
// the embed action's retry-with-backoff path.
//
// Attempts are counted per input text, not globally: saving a person embeds
// the person AND each line of their note as its own memory, so "the second
// attempt" has to mean the second attempt at that text rather than the
// second network call the test happened to see.
function stubEmbeddingsSequence(
  respond: (attempt: number, input: string) => Response,
): { attemptsFor: (input: string) => number } {
  const realFetch = globalThis.fetch;
  const attempts = new Map<string, number>();
  vi.stubGlobal(
    "fetch",
    async (input: RequestInfo | URL, init?: RequestInit) => {
      const raw = String(input);
      let url: URL;
      try {
        url = new URL(raw);
      } catch {
        return realFetch(input, init);
      }
      if (url.hostname === "api.openai.com" && url.pathname.includes("/embeddings")) {
        const body = JSON.parse(String(init?.body ?? "{}")) as {
          input?: string;
        };
        const text = body.input ?? "";
        const attempt = attempts.get(text) ?? 0;
        attempts.set(text, attempt + 1);
        return respond(attempt, text);
      }
      return realFetch(input, init);
    },
  );
  return { attemptsFor: (input) => attempts.get(input) ?? 0 };
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

// addPerson requires identity and a story (a handle and a note) so a manual
// add stays searchable and referenceable later. Tests not exercising that
// rule spread this minimal valid payload first and override what they test.
//
// contactHandles is a getter, not a fixed array: addPerson now dedups on the
// handle (identity brief, task 2), and dozens of tests below spread this
// fixture more than once for the same user to seed unrelated people. A fixed
// value would fold every one of those onto the first person instead of
// creating the rest -- a getter hands out a fresh number each time the
// fixture is spread, so every call keeps meaning "a new person" unless a
// test overrides contactHandles itself to test identity on purpose.
let nextUnlistedNumber = 0;
const manualAdd = {
  get contactHandles() {
    return [{ platform: "phone", value: `unlisted${nextUnlistedNumber++}` }];
  },
  context: "met before this test",
};

// What buildEmbedText produces for `addPerson({ ...manualAdd, name: "Maya
// Chen" })`. The retry tests count attempts against this exact string so a
// memory row's own embed cannot be mistaken for one of the person's retries.
const PERSON_EMBED_TEXT = `Maya Chen\n${manualAdd.context}`;

describe("appendContext", () => {
  test("a genuinely new note appends on its own line", () => {
    expect(appendContext("first note", "second note")).toEqual({
      context: "first note\nsecond note",
      noteTruncated: false,
    });
  });

  test("no note is a no-op", () => {
    expect(appendContext("first note", undefined)).toEqual({
      context: "first note",
      noteTruncated: false,
    });
  });

  test("nothing existing yet: the note becomes the whole context", () => {
    expect(appendContext(undefined, "first note")).toEqual({
      context: "first note",
      noteTruncated: false,
    });
    expect(appendContext("", "first note")).toEqual({
      context: "first note",
      noteTruncated: false,
    });
  });

  // At-least-once replay -- a queued capture retried, a conflict retried by
  // the client after a dropped response -- must not double the same note
  // into the context every time the same write lands twice.
  test("a note already present in the context is not appended a second time", () => {
    expect(appendContext("met at the market", "met at the market")).toEqual({
      context: "met at the market",
      noteTruncated: false,
    });
    expect(
      appendContext("first note\nmet at the market", "met at the market"),
    ).toEqual({
      context: "first note\nmet at the market",
      noteTruncated: false,
    });
  });

  // A note that merely shares a word with the existing context is not a
  // replay of anything -- only the whole note text, verbatim, counts.
  test("a note that only overlaps in part still appends", () => {
    expect(appendContext("met at the market", "met her sister too")).toEqual({
      context: "met at the market\nmet her sister too",
      noteTruncated: false,
    });
  });

  // R4: existing.includes(note) was a substring check, not a replay check --
  // "Acme" reads as contained inside "Met at Acme" even though it is a
  // genuinely new, shorter note about the same person. Replay detection has
  // to match a whole stored line, not any substring of the whole blob.
  test("a note contained within a longer existing line still appends", () => {
    expect(appendContext("Met at Acme", "Acme")).toEqual({
      context: "Met at Acme\nAcme",
      noteTruncated: false,
    });
  });

  // The other half of the same fix: a genuine replay -- the exact text of an
  // existing line, byte for byte -- still has to skip, same as before.
  test("a note byte-identical to an existing line still skips", () => {
    expect(appendContext("Met at Acme", "Met at Acme")).toEqual({
      context: "Met at Acme",
      noteTruncated: false,
    });
    expect(appendContext("first note\nMet at Acme", "Met at Acme")).toEqual({
      context: "first note\nMet at Acme",
      noteTruncated: false,
    });
  });
});

test("addPerson creates a person owned by the caller with a timestamp", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);

  const id = await addPersonId(as, { ...manualAdd, name: "Maya Chen" });

  const person = await t.run((ctx) => ctx.db.get("people", id));
  expect(person?.name).toBe("Maya Chen");
  expect(person?.userId).toBe(userId);
  expect(typeof person?.updatedAt).toBe("number");
});

test("addPerson rejects a blank name", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await expect(
    as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "   " }),
  ).rejects.toThrow("Name is required");
});

test("addPerson requires a contact handle and a note", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await expect(
    as.mutation(api.people.addPersonWithOutcome, {
      ...manualAdd,
      name: "Maya",
      contactHandles: [],
    }),
  ).rejects.toThrow("A contact handle is required");
  await expect(
    as.mutation(api.people.addPersonWithOutcome, {
      name: "Maya",
      context: manualAdd.context,
    }),
  ).rejects.toThrow("A contact handle is required");
  await expect(
    as.mutation(api.people.addPersonWithOutcome, {
      ...manualAdd,
      name: "Maya",
      context: "   ",
    }),
  ).rejects.toThrow("A note is required");
  await expect(
    as.mutation(api.people.addPersonWithOutcome, {
      name: "Maya",
      contactHandles: manualAdd.contactHandles,
    }),
  ).rejects.toThrow("A note is required");
});

test("addPerson rejects an unauthenticated caller", async () => {
  const t = convexTest(schema, modules);
  await expect(
    t.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Maya" }),
  ).rejects.toThrow("Not signed in");
});

// ------------------------------------------------- identity on creation

test("addPerson twice with the same handle lands on one person, not two", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const handle = { platform: "instagram", value: "mai.makes" };

  const first = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    contactHandles: [handle],
    context: "met at the ceramics market",
  });
  expect(first.status).toBe("created");
  if (first.status !== "created") throw new Error("unreachable");

  // A different name, the same handle: identity beats what the second call
  // happened to type, the same doctrine saveSharedProfile already keeps.
  const second = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai T.",
    contactHandles: [handle],
    context: "ran into her again downtown",
  });
  expect(second.status).toBe("attached");
  if (second.status !== "attached" && second.status !== "already") {
    throw new Error("unreachable");
  }
  expect(second.personId).toBe(first.personId);

  const people = await t.run((ctx) =>
    ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect(),
  );
  expect(people).toHaveLength(1);
  expect(people[0].name).toBe("Mai Tran");
  expect(people[0].context).toBe(
    "met at the ceramics market\nran into her again downtown",
  );
});

// S4: an open SPA tab from before addPerson ever returned an outcome object
// still calls "people:addPerson" by that literal name and assigns the
// result straight to a person id. The legacy contract is restored here so
// those tabs keep working; the current, outcome-shaped mutation moved to
// addPersonWithOutcome (src/SearchAdd.tsx calls that one).
describe("the legacy addPerson contract old tabs still depend on", () => {
  test("returns a bare person id, not an outcome object", async () => {
    const t = convexTest(schema, modules);
    const { userId, as } = await asNewUser(t);

    const id = await as.mutation(api.people.addPerson, {
      ...manualAdd,
      name: "Maya Chen",
    });

    // A plain Id<"people"> is a string; an outcome object is not.
    expect(typeof id).toBe("string");
    const person = await t.run((ctx) => ctx.db.get("people", id));
    expect(person?.name).toBe("Maya Chen");
    expect(person?.userId).toBe(userId);
  });

  test("dedups silently: a handle that already belongs to someone hands back their id, not an error", async () => {
    const t = convexTest(schema, modules);
    const { as } = await asNewUser(t);
    const first = await as.mutation(api.people.addPerson, {
      name: "Binh Le",
      contactHandles: [{ platform: "instagram", value: "binh.le" }],
      context: "gave me his card",
    });

    const second = await as.mutation(api.people.addPerson, {
      name: "Binh (misspelled)",
      contactHandles: [{ platform: "instagram", value: "binh.le" }],
      context: "he does event photography too",
    });

    expect(second).toBe(first);
    const person = await t.run((ctx) => ctx.db.get("people", first));
    expect(person?.name).toBe("Binh Le");
    expect(person?.context).toBe(
      "gave me his card\nhe does event photography too",
    );
  });

  test("throws on a conflict rather than returning something an old tab could misuse", async () => {
    const t = convexTest(schema, modules);
    const { as } = await asNewUser(t);
    const a = await as.mutation(api.people.addPerson, {
      name: "Ada Lovelace",
      contactHandles: [{ platform: "instagram", value: "ada" }],
      context: "the analytical engine talk",
    });
    const b = await as.mutation(api.people.addPerson, {
      name: "Grace Hopper",
      contactHandles: [{ platform: "linkedin", value: "grace-hopper" }],
      context: "the compiler talk",
    });
    const before = await t.run((ctx) =>
      ctx.db
        .query("people")
        .withIndex("by_user")
        .collect(),
    );

    await expect(
      as.mutation(api.people.addPerson, {
        name: "Someone I misfiled",
        contactHandles: [
          { platform: "instagram", value: "ada" },
          { platform: "linkedin", value: "grace-hopper" },
        ],
        context: "not sure who this is",
      }),
    ).rejects.toThrow();

    // Nothing written: no third person, and neither existing person touched.
    const after = await t.run((ctx) =>
      ctx.db
        .query("people")
        .withIndex("by_user")
        .collect(),
    );
    expect(after).toEqual(before);
    expect(a).not.toBe(b);
  });

  // The rich behavior underneath (provenance, platformId-preferred dedup,
  // the 8-handle cap) is identical either way -- only the shape of the
  // answer differs by which mutation name a client happens to call.
  test("carries the same dedup behavior addPersonWithOutcome has, just answered differently", async () => {
    const t = convexTest(schema, modules);
    const { as } = await asNewUser(t);
    const id = await as.mutation(api.people.addPerson, {
      name: "Mai Tran",
      contactHandles: [
        { platform: "instagram", value: "old.username", platformId: "ig-12345" },
      ],
      context: "gave me her card",
    });

    // A rename via platformId still resolves to the same person, the same
    // way it does through addPersonWithOutcome.
    const renamed = await as.mutation(api.people.addPerson, {
      name: "Mai Tran",
      contactHandles: [
        { platform: "instagram", value: "new.username", platformId: "ig-12345" },
      ],
      context: "saw her new handle",
    });
    expect(renamed).toBe(id);
    const person = await t.run((ctx) => ctx.db.get("people", id));
    expect(person?.contactHandles).toEqual([
      expect.objectContaining({ value: "new.username", platformId: "ig-12345" }),
    ]);
  });
});

test("addPerson on a handle owned by someone else merges into them instead of making a new person", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const owner = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Binh Le",
    contactHandles: [{ platform: "phone", value: "+1 415 555 0123" }],
    context: "gave me his card",
  });
  expect(owner.status).toBe("created");
  if (owner.status !== "created") throw new Error("unreachable");

  // Typed without knowing Binh already exists: identity resolves on the
  // handle, not on the name the second call happened to use. Both forms
  // carry their own country code -- this call goes straight to the mutation,
  // bypassing the browser-region normalization src/reach.ts does on web, so
  // a bare "4155550123" here would key on digits alone, not this E.164 form
  // (handleKeys.ts task 1: the server never guesses a region).
  const result = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Binh (photography)",
    contactHandles: [{ platform: "phone", value: "+14155550123" }],
    context: "he does event photography too",
  });
  expect(result.status).toBe("attached");
  if (result.status !== "attached") throw new Error("unreachable");
  expect(result.personId).toBe(owner.personId);

  const people = await t.run((ctx) =>
    ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect(),
  );
  expect(people).toHaveLength(1);
  expect(people[0].context).toContain("he does event photography too");
});

test("addPerson refuses to pick a winner when two submitted handles belong to two different people", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const a = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Ada Lovelace",
    contactHandles: [{ platform: "instagram", value: "ada" }],
    context: "the analytical engine talk",
  });
  const b = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Grace Hopper",
    contactHandles: [{ platform: "linkedin", value: "grace-hopper" }],
    context: "the compiler talk",
  });
  if (a.status !== "created" || b.status !== "created") {
    throw new Error("unreachable");
  }
  const before = await t.run((ctx) =>
    ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect(),
  );

  const result = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Someone I misfiled",
    contactHandles: [
      { platform: "instagram", value: "ada" },
      { platform: "linkedin", value: "grace-hopper" },
    ],
    context: "not sure who this is",
  });
  expect(result.status).toBe("conflict");
  if (result.status !== "conflict") throw new Error("unreachable");
  expect(new Set(result.personIds)).toEqual(new Set([a.personId, b.personId]));

  // Nothing written: no third person, and neither existing person touched.
  const after = await t.run((ctx) =>
    ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect(),
  );
  expect(after).toEqual(before);
});

test("addPerson attaches to the person the caller picked, skipping the create branch", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const mai = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tr\u1EA7n",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });

  const result = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    contactHandles: [{ platform: "linkedin", value: "mai-tran-8a91b2" }],
    context: "leads design at Photon",
    attachToPersonId: mai,
  });
  expect(result).toEqual({
    status: "attached",
    personId: mai,
    noteTruncated: false,
    handleDropped: false,
  });

  const person = await as.query(api.people.getPerson, { id: mai });
  expect(displayOnly(person?.contactHandles)).toEqual([
    { platform: "instagram", value: "mai.makes" },
    { platform: "linkedin", value: "mai-tran-8a91b2" },
  ]);
  expect(person?.context).toContain("leads design at Photon");

  // No second person was created for the pick.
  const people = await as.query(api.people.searchDirectory, {});
  expect(people).toHaveLength(1);
});

test("addPerson refuses to steal a handle onto the picked person when it already belongs to someone else", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const ada = await addPersonId(as, {
    name: "Ada Lovelace",
    contactHandles: [{ platform: "instagram", value: "ada" }],
    context: "the analytical engine talk",
  });
  const grace = await addPersonId(as, {
    name: "Grace Hopper",
    contactHandles: [{ platform: "linkedin", value: "grace-hopper" }],
    context: "the compiler talk",
  });
  const before = await t.run((ctx) => ctx.db.get("people", grace));

  // The caller picked Grace, but this handle is provably Ada's -- the save
  // must refuse, not silently relabel Ada's account as an attach to Grace.
  const result = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Someone I misfiled",
    contactHandles: [{ platform: "instagram", value: "ada" }],
    context: "not sure who this is",
    attachToPersonId: grace,
  });
  expect(result).toEqual({ status: "conflict", personIds: [ada] });

  const after = await t.run((ctx) => ctx.db.get("people", grace));
  expect(after).toEqual(before);
});

test("addPerson refuses to attach to a person that is not the caller's", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  const theirs = await addPersonId(other.as, {
    name: "Rao",
    contactHandles: [{ platform: "phone", value: "unlisted-not-mine-1" }],
    context: "met at a talk",
  });

  await expect(
    me.as.mutation(api.people.addPersonWithOutcome, {
      name: "Someone",
      contactHandles: [{ platform: "instagram", value: "someone" }],
      context: "a guess",
      attachToPersonId: theirs,
    }),
  ).rejects.toThrow();
});

test("editPerson refuses to steal a handle a different person already owns", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const owner = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Ada Lovelace",
    contactHandles: [{ platform: "instagram", value: "ada" }],
    context: "the analytical engine talk",
  });
  const editing = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Grace Hopper",
    contactHandles: [{ platform: "linkedin", value: "grace-hopper" }],
    context: "the compiler talk",
  });
  if (owner.status !== "created" || editing.status !== "created") {
    throw new Error("unreachable");
  }
  const before = await t.run((ctx) => ctx.db.get("people", editing.personId));

  const result = await as.mutation(api.people.editPerson, {
    id: editing.personId,
    contactHandles: [{ platform: "instagram", value: "ada" }],
  });
  expect(result).toEqual({
    status: "handle_taken",
    personId: owner.personId,
    name: "Ada Lovelace",
  });

  const after = await t.run((ctx) => ctx.db.get("people", editing.personId));
  expect(after).toEqual(before);
  const owningRows = await t.run((ctx) =>
    ctx.db
      .query("personHandles")
      .withIndex("by_person", (q) => q.eq("personId", owner.personId))
      .collect(),
  );
  expect(owningRows).toHaveLength(1);
});

// The gap: findHandleOwner stops at the first hit, so a platformId-first
// lookup that resolves straight to the person being edited never tries the
// value on its own -- editPerson read that as "renaming my own handle" and
// skipped the ownership check entirely, letting a rename land on a value B
// already, provably, owns. Same refusal saveSharedProfile's own
// id-preferred rename gets.
test("editPerson refuses an id-preferred rename onto a value someone else already owns", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);

  const b = await as.mutation(api.people.addPersonWithOutcome, {
    name: "New Person",
    context: "met at the market",
    contactHandles: [{ platform: "instagram", value: "new.username" }],
  });
  if (b.status !== "created") throw new Error("unreachable");
  const a = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "gave me her card",
    contactHandles: [
      { platform: "instagram", value: "old.username", platformId: "ig-12345" },
    ],
  });
  if (a.status !== "created") throw new Error("unreachable");

  const result = await as.mutation(api.people.editPerson, {
    id: a.personId,
    contactHandles: [
      { platform: "instagram", value: "new.username", platformId: "ig-12345" },
    ],
  });

  expect(result).toEqual({
    status: "handle_taken",
    personId: b.personId,
    name: "New Person",
  });

  // Neither person's handle moved.
  const aAfter = await as.query(api.people.getPerson, { id: a.personId });
  expect(displayOnly(aAfter?.contactHandles)).toEqual([
    { platform: "instagram", value: "old.username" },
  ]);
  const bAfter = await as.query(api.people.getPerson, { id: b.personId });
  expect(displayOnly(bAfter?.contactHandles)).toEqual([
    { platform: "instagram", value: "new.username" },
  ]);
  // "new.username" still indexes to exactly one person (B), not two.
  const owners = await t.run((ctx) =>
    ctx.db
      .query("personHandles")
      .withIndex("by_user_and_platform_and_valueKey", (q) =>
        q.eq("userId", userId).eq("platform", "instagram").eq("valueKey", "new.username"),
      )
      .collect(),
  );
  expect(owners.map((row) => row.personId)).toEqual([b.personId]);
});

test("searchPeople matches the caller's people by name and excludes others", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  await me.as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Maya Chen" });
  await me.as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Felix Ng" });
  await other.as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Maya Rao" });

  const results = await me.as.query(api.people.searchPeople, { query: "Maya" });
  expect(results.map((p) => p.name)).toEqual(["Maya Chen"]);
});

test("searchPeople with an empty query returns only the caller's recent people", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  await me.as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Maya Chen" });
  await me.as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Felix Ng" });
  // Another user's person must never appear in my empty-query results.
  await other.as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Rao" });

  const results = await me.as.query(api.people.searchPeople, { query: "  " });
  expect(results.map((p) => p.name).sort()).toEqual(["Felix Ng", "Maya Chen"]);
});

// S7: Convex's own search index does not typo-match ("Meya" never surfaces
// "Maya"), and the sky's own two subscriptions (searchPeople) are both
// scoped to a query or capped at the 20 most recent -- neither is a pool
// the client can run its own edit-distance suggester over and expect a
// typo'd name to be found. listPersonNames is that pool: every one of the
// caller's people, name and handles only, light enough to load in full.
test("listPersonNames returns the caller's people, names and handles only, and none of another user's", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  const mine = await addPersonId(me.as, {
    name: "Maya Chen",
    contactHandles: [{ platform: "instagram", value: "maya.chen" }],
    context: "met at the market",
  });
  await other.as.mutation(api.people.addPersonWithOutcome, {
    name: "Someone Else",
    contactHandles: [{ platform: "instagram", value: "someone" }],
    context: "met elsewhere",
  });

  const results = await me.as.query(api.people.listPersonNames, {});

  expect(results).toEqual([
    {
      _id: mine,
      name: "Maya Chen",
      contactHandles: [
        expect.objectContaining({ platform: "instagram", value: "maya.chen" }),
      ],
    },
  ]);
});

test("listPersonNames requires an authenticated caller", async () => {
  const t = convexTest(schema, modules);
  await expect(t.query(api.people.listPersonNames, {})).rejects.toThrow();
});

test("getPerson returns the caller's person and null for another user's", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  const myId = await addPersonId(me.as, { ...manualAdd, name: "Maya" });
  const otherId = await addPersonId(other.as, {
    ...manualAdd,
    name: "Rao",
  });

  expect((await me.as.query(api.people.getPerson, { id: myId }))?.name).toBe(
    "Maya",
  );
  expect(await me.as.query(api.people.getPerson, { id: otherId })).toBeNull();
});

test("updatePerson saves link and context and bumps updatedAt", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const id = await addPersonId(me.as, { ...manualAdd, name: "Maya" });
  const before = await t.run((ctx) => ctx.db.get(id));

  // Advance the clock so the new updatedAt is provably later, not just
  // "not earlier" (Date.now() alone could tie within the same millisecond).
  vi.advanceTimersByTime(1000);

  await me.as.mutation(api.people.updatePerson, {
    id,
    link: "https://example.com",
    context: "recruiting agents at Photon",
  });

  const after = await t.run((ctx) => ctx.db.get(id));
  expect(after?.link).toBe("https://example.com");
  expect(after?.context).toBe("recruiting agents at Photon");
  expect(after!.updatedAt).toBeGreaterThan(before!.updatedAt);
});

test("updatePerson rejects updating another user's person", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  const otherId = await addPersonId(other.as, {
    ...manualAdd,
    name: "Rao",
  });

  await expect(
    me.as.mutation(api.people.updatePerson, { id: otherId, context: "x" }),
  ).rejects.toThrow("Person not found");
});

test("updatePerson with omitted fields clears them (undefined unsets)", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const id = await addPersonId(me.as, { ...manualAdd, name: "Maya" });
  await me.as.mutation(api.people.updatePerson, {
    id,
    link: "https://example.com",
    context: "recruiting agents",
  });

  // Saving with both fields omitted models the detail screen clearing the
  // inputs; the mutation must unset link and context, not leave them stale.
  await me.as.mutation(api.people.updatePerson, { id });

  const after = await t.run((ctx) => ctx.db.get("people", id));
  expect(after?.link).toBeUndefined();
  expect(after?.context).toBeUndefined();
});

test("people functions reject an unauthenticated caller", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const id = await addPersonId(me.as, { ...manualAdd, name: "Maya" });

  await expect(t.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "x" })).rejects.toThrow(
    "Not signed in",
  );
  await expect(t.query(api.people.searchPeople, { query: "" })).rejects.toThrow(
    "Not signed in",
  );
  await expect(t.query(api.people.getPerson, { id })).rejects.toThrow(
    "Not signed in",
  );
  await expect(
    t.mutation(api.people.updatePerson, { id }),
  ).rejects.toThrow("Not signed in");
  await expect(
    t.mutation(api.people.deletePerson, { personId: id }),
  ).rejects.toThrow("Not signed in");
});

// ------------------------------------------------------------ projections

test("searchPeople and getPerson never leak embedding, embeddedText, or userId", async () => {
  stubEmbeddings(new Array(1536).fill(0));
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const id = await addPersonId(as, { ...manualAdd, name: "Maya Chen" });
  // Run the scheduled embed so the person actually has embedding fields set
  // -- the leak this test guards against can only happen once they exist.
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  const stored = await t.run((ctx) => ctx.db.get("people", id));
  expect(stored?.embedding).toBeDefined();

  const searchResults = await as.query(api.people.searchPeople, {
    query: "Maya",
  });
  expect(searchResults).toHaveLength(1);
  expect(searchResults[0]).not.toHaveProperty("embedding");
  expect(searchResults[0]).not.toHaveProperty("embeddedText");
  expect(searchResults[0]).not.toHaveProperty("userId");

  const person = await as.query(api.people.getPerson, { id });
  expect(person).not.toHaveProperty("embedding");
  expect(person).not.toHaveProperty("embeddedText");
  expect(person).not.toHaveProperty("userId");
});

// -------------------------------------------------------------- deletion

test("deletePerson removes the person and its screenshot", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const screenshotId = await t.run((ctx) =>
    ctx.storage.store(new Blob(["x"], { type: "image/png" })),
  );
  const personId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Maya",
      updatedAt: Date.now(),
      screenshotId,
    }),
  );

  await as.mutation(api.people.deletePerson, { personId });

  expect(await t.run((ctx) => ctx.db.get("people", personId))).toBeNull();
  expect(await t.run((ctx) => ctx.storage.getUrl(screenshotId))).toBeNull();
});

test("deletePerson rejects deleting another user's person", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  const otherId = await addPersonId(other.as, {
    ...manualAdd,
    name: "Rao",
  });

  await expect(
    me.as.mutation(api.people.deletePerson, { personId: otherId }),
  ).rejects.toThrow("Person not found");
  expect(await t.run((ctx) => ctx.db.get("people", otherId))).not.toBeNull();
});

// --------------------------------------------------------- rate limiting

test("addPerson is rate-limited per caller (wiring check)", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  await as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Maya" });

  const window = await t.run((ctx) =>
    ctx.db
      .query("rateLimits")
      .withIndex("by_user_action", (q) =>
        q.eq("userId", userId).eq("action", "addPerson"),
      )
      .unique(),
  );
  expect(window?.count).toBe(1);
});

test("addPerson throttles a burst past its per-minute limit", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  for (let i = 0; i < 30; i++) {
    await as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: `Person ${i}` });
  }
  await expect(
    as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "One too many" }),
  ).rejects.toThrow("Too many requests -- please wait a moment");

  vi.setSystemTime(Date.now() + 60_000);
  await expect(
    as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "A new window" }),
  ).resolves.toEqual({ status: "created", personId: expect.any(String) });
});

test("updatePerson is rate-limited per caller (wiring check)", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const id = await addPersonId(as, { ...manualAdd, name: "Maya" });
  await as.mutation(api.people.updatePerson, { id, context: "x" });

  const window = await t.run((ctx) =>
    ctx.db
      .query("rateLimits")
      .withIndex("by_user_action", (q) =>
        q.eq("userId", userId).eq("action", "updatePerson"),
      )
      .unique(),
  );
  expect(window?.count).toBe(1);
});

// ------------------------------------------------------- normalizeName

describe("normalizeName", () => {
  test("lowercases, strips diacritics, and collapses whitespace", () => {
    expect(normalizeName("Nguyen Van Dung")).toBe("nguyen van dung");
    expect(normalizeName("  Maya   Chen  ")).toBe("maya chen");
  });

  test("folds a fully-accented Vietnamese phrase down to plain ASCII", () => {
    expect(normalizeName("Nguy\u1ec5n V\u0103n D\u0169ng")).toBe(
      "nguyen van dung",
    );
  });

  test("folds the Vietnamese D-stroke, which NFD cannot decompose on its own", () => {
    // "\u0110un \u0110un" is "Dun Dun" typed with the D-stroke letter.
    expect(normalizeName("\u0110un \u0110un")).toBe("dun dun");
    expect(normalizeName("d\u1ee9a \u0111\u1ecfi")).toBe("dua doi");
  });
});

// -------------------------------------------------- accent-insensitive search

test("searchPeople finds an accented name via an unaccented query", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Nguy\u1ec5n V\u0103n D\u0169ng" });

  const results = await as.query(api.people.searchPeople, { query: "dung" });
  expect(results.map((p) => p.name)).toEqual(["Nguy\u1ec5n V\u0103n D\u0169ng"]);
});

test("searchPeople finds an unaccented name via an accented query", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Dung" });

  const results = await as.query(api.people.searchPeople, {
    query: "D\u0169ng",
  });
  expect(results.map((p) => p.name)).toEqual(["Dung"]);
});

test("searchPeople finds the D-stroke name via a plain-D query", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "\u0110un \u0110un" });

  const results = await as.query(api.people.searchPeople, { query: "dun" });
  expect(results.map((p) => p.name)).toEqual(["\u0110un \u0110un"]);
});

test("searchPeople keeps user isolation on the normalized-name index", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  await me.as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "D\u0169ng" });
  await other.as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "D\u0169ng Two" });

  const results = await me.as.query(api.people.searchPeople, { query: "dung" });
  expect(results.map((p) => p.name)).toEqual(["D\u0169ng"]);
});

test("searchPeople with a query that normalizes to empty falls back to recent people", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Maya Chen" });

  // A combining mark alone (U+0301, acute accent) normalizes to "".
  const results = await as.query(api.people.searchPeople, {
    query: "\u0301",
  });
  expect(results.map((p) => p.name)).toEqual(["Maya Chen"]);
});

test("backfillNormalizedNames patches rows missing normalizedName and skips the rest", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  const legacyId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "D\u0169ng",
      updatedAt: Date.now(),
    }),
  );
  const currentId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Maya",
      normalizedName: "maya",
      updatedAt: Date.now(),
    }),
  );

  const patched = await t.mutation(internal.people.backfillNormalizedNames, {});
  expect(patched).toBe(1);

  const legacy = await t.run((ctx) => ctx.db.get("people", legacyId));
  expect(legacy?.normalizedName).toBe("dung");
  const current = await t.run((ctx) => ctx.db.get("people", currentId));
  expect(current?.normalizedName).toBe("maya");
});

test("backfillEmbeddings continues past a failing row", async () => {
  // The daily cron runs this unattended; one poisoned row must not strand
  // everyone queued behind it.
  // Poisoned by which row it is, not by which call it is: the sweep embeds
  // people and memories on the same endpoint, so an ordinal would pick a
  // victim at random.
  const stub = stubEmbeddingsSequence((_attempt, input) =>
    input.includes("First Failing")
      ? new Response("upstream error", { status: 500 })
      : Response.json({ data: [{ embedding: new Array(1536).fill(0.1) }] }),
  );
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  const firstId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "First Failing",
      normalizedName: "first failing",
      updatedAt: Date.now(),
    }),
  );
  const secondId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Second Fine",
      normalizedName: "second fine",
      updatedAt: Date.now(),
    }),
  );

  const embedded = await t.action(internal.people.backfillEmbeddings, {});
  expect(embedded).toBe(1);
  expect(stub.attemptsFor("First Failing")).toBe(1);
  expect(stub.attemptsFor("Second Fine")).toBe(1);

  const first = await t.run((ctx) => ctx.db.get("people", firstId));
  expect(first?.embedding).toBeUndefined();
  const second = await t.run((ctx) => ctx.db.get("people", secondId));
  expect(second?.embedding).toBeDefined();
});

// ------------------------------------------------------- context length cap

test("addPerson rejects context over 4000 characters", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await expect(
    as.mutation(api.people.addPersonWithOutcome, {
      ...manualAdd,
      name: "Maya",
      context: "x".repeat(4001),
    }),
  ).rejects.toThrow("Context is too long -- keep it under 4000 characters");
});

test("addPerson accepts context at exactly 4000 characters", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await addPersonId(as, {
    ...manualAdd,
    name: "Maya",
    context: "x".repeat(4000),
  });
  const person = await t.run((ctx) => ctx.db.get("people", id));
  expect(person?.context).toHaveLength(4000);
});

test("updatePerson rejects context over 4000 characters", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await addPersonId(as, { ...manualAdd, name: "Maya" });
  await expect(
    as.mutation(api.people.updatePerson, {
      id,
      context: "x".repeat(4001),
    }),
  ).rejects.toThrow("Context is too long -- keep it under 4000 characters");
});

// -------------------------------------------------------- embed input safety

test("embed slices an over-long combined text before requesting an embedding", async () => {
  stubEmbeddings(new Array(1536).fill(0.2));
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  // Bypass addPerson's 4000-char cap to model legacy data or a huge headline
  // written directly by the capture pipeline (out of scope here).
  const id = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Maya Chen",
      context: "x".repeat(9000),
      updatedAt: Date.now(),
    }),
  );

  await t.run((ctx) =>
    ctx.scheduler.runAfter(0, internal.people.embed, { personId: id }),
  );
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const stored = await t.run((ctx) => ctx.db.get("people", id));
  expect(stored?.embedding).toBeDefined();
  expect(stored?.embeddedText).toHaveLength(8000);
});

// ------------------------------------------------------------ embed retries

test("embed retries after a failure and succeeds on the next attempt", async () => {
  const stub = stubEmbeddingsSequence((attempt) =>
    attempt === 0
      ? new Response("rate limited", { status: 429 })
      : Response.json({ data: [{ embedding: new Array(1536).fill(0.1) }] }),
  );

  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await addPersonId(as, { ...manualAdd, name: "Maya Chen" });

  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const stored = await t.run((ctx) => ctx.db.get("people", id));
  expect(stored?.embedding).toBeDefined();
  // The person's own embed input, not the memory row's, which holds the
  // bare note line and embeds on its own schedule.
  expect(stub.attemptsFor(PERSON_EMBED_TEXT)).toBe(2);
});

test("embed gives up after 3 total attempts without throwing", async () => {
  const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
  const stub = stubEmbeddingsSequence(
    () => new Response("boom", { status: 500 }),
  );

  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await addPersonId(as, { ...manualAdd, name: "Maya Chen" });

  await expect(
    t.finishAllScheduledFunctions(vi.runAllTimers),
  ).resolves.not.toThrow();

  const stored = await t.run((ctx) => ctx.db.get("people", id));
  expect(stored?.embedding).toBeUndefined();
  expect(stub.attemptsFor(PERSON_EMBED_TEXT)).toBe(3);
  expect(consoleError).toHaveBeenCalled();

  consoleError.mockRestore();
});

// ----------------------------------------------------- structured attributes

test("addPerson stores city, company, and role and returns them from getPerson", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const id = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tran",
    company: " LinkedIn ",
    role: "Design Engineer",
    city: { name: "S\u00e0i G\u00f2n", country: "Vietnam" },
  });

  const person = await as.query(api.people.getPerson, { id });
  expect(person?.company).toBe("LinkedIn");
  expect(person?.role).toBe("Design Engineer");
  expect(person?.city).toEqual({
    name: "S\u00e0i G\u00f2n",
    country: "Vietnam",
  });

  // The filter keys are Phase 3 chip infrastructure: derived server-side,
  // accent-folded, and never part of the client shape.
  const stored = await t.run((ctx) => ctx.db.get("people", id));
  expect(stored?.companyKey).toBe("linkedin");
  expect(stored?.roleKey).toBe("design engineer");
  expect(stored?.cityKey).toBe("sai gon");
});

test("addPerson rejects blank structured attributes", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await expect(
    as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Mai", company: "  " }),
  ).rejects.toThrow("Company cannot be blank");
  await expect(
    as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Mai", city: { name: " " } }),
  ).rejects.toThrow("City cannot be blank");
});

// ---------------------------------------------------------- contact handles

// ------------------------------------------------------------ provenance

test("addPerson stores and round-trips source, platformId and addedAt on a contact handle", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const result = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "gave me her card at the meetup",
    contactHandles: [
      {
        platform: "instagram",
        value: "mai.makes",
        source: "proven",
        platformId: "ig-9001",
      },
    ],
  });
  expect(result.status).toBe("created");
  if (result.status !== "created") throw new Error("unreachable");

  const person = await as.query(api.people.getPerson, { id: result.personId });
  expect(person?.contactHandles).toEqual([
    {
      platform: "instagram",
      value: "mai.makes",
      source: "proven",
      platformId: "ig-9001",
      addedAt: expect.any(Number),
    },
  ]);
});

test("addPerson defaults an unstated handle source to typed", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const result = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "gave me her card",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });
  if (result.status !== "created") throw new Error("unreachable");

  const person = await as.query(api.people.getPerson, { id: result.personId });
  expect(person?.contactHandles?.[0].source).toBe("typed");
  expect(person?.contactHandles?.[0].platformId).toBeUndefined();
});

test("editPerson defaults an unstated handle source to typed", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await addPersonId(as, { ...manualAdd, name: "Mai Tran" });

  const edited = await editPersonOk(as, {
    id,
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });
  expect(edited.contactHandles?.[0].source).toBe("typed");
});

// PersonFieldEditors on iOS sends handles as bare {platform, value} -- no
// source, platformId or addedAt -- even for a handle that already carries
// all three (e.g. it was proven by Composio, or has been on the card for
// months). The bug: editPerson used to treat every submitted handle as
// freshly typed, so reordering or re-saving an unrelated field silently
// wiped provenance a client never meant to touch. Fixed server-side so every
// client is protected, not just ones that remember to resend metadata.
test("editPerson carries forward provenance for a handle whose value did not change", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const id = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Tony",
      normalizedName: "tony",
      contactHandles: [
        {
          platform: "linkedin",
          value: "tony-buildd",
          source: "proven",
          platformId: "urn:li:person:abc123",
          addedAt: Date.UTC(2026, 0, 1),
        },
      ],
      updatedAt: Date.now(),
    }),
  );

  // A bare {platform, value} resubmit -- exactly what PersonFieldEditors
  // sends, and what a client that only reordered the handles list produces
  // for every entry regardless of which one moved.
  const edited = await editPersonOk(as, {
    id,
    contactHandles: [{ platform: "linkedin", value: "tony-buildd" }],
  });

  expect(edited.contactHandles?.[0]).toEqual({
    platform: "linkedin",
    value: "tony-buildd",
    source: "proven",
    platformId: "urn:li:person:abc123",
    addedAt: Date.UTC(2026, 0, 1),
  });
});

test("editPerson does not carry provenance onto a changed value on the same platform", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const id = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Tony",
      normalizedName: "tony",
      contactHandles: [
        {
          platform: "linkedin",
          value: "old-slug",
          source: "proven",
          platformId: "urn:li:person:abc123",
          addedAt: Date.UTC(2026, 0, 1),
        },
      ],
      updatedAt: Date.now(),
    }),
  );

  // A DIFFERENT value on the same platform is a different account: the old
  // one's proof does not transfer just because the platform slot is the same.
  const edited = await editPersonOk(as, {
    id,
    contactHandles: [{ platform: "linkedin", value: "new-slug" }],
  });

  expect(edited.contactHandles?.[0].platform).toBe("linkedin");
  expect(edited.contactHandles?.[0].value).toBe("new-slug");
  expect(edited.contactHandles?.[0].source).toBe("typed");
  expect(edited.contactHandles?.[0].platformId).toBeUndefined();
  expect(edited.contactHandles?.[0].addedAt).not.toBe(Date.UTC(2026, 0, 1));
});

// An explicit submission still wins over what was already there -- a client
// that DOES know the platformId (iOS's own X-rename flow, S2/S3) must be
// able to set it even when the value is unchanged.
test("editPerson lets an explicit submission override carried-forward provenance", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const id = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Tony",
      normalizedName: "tony",
      contactHandles: [
        { platform: "x", value: "tonybuildd", source: "typed" },
      ],
      updatedAt: Date.now(),
    }),
  );

  const edited = await editPersonOk(as, {
    id,
    contactHandles: [
      { platform: "x", value: "tonybuildd", source: "proven", platformId: "x_id_1" },
    ],
  });

  expect(edited.contactHandles?.[0].source).toBe("proven");
  expect(edited.contactHandles?.[0].platformId).toBe("x_id_1");
});

// W2: an equal value used to let a submitted platformId silently overwrite
// whatever this person's own handle already had proven -- exactly
// mergeHandleIntoOwner's X1 rule (people.ts's equal-valueKey branch, the
// same file): both ids present and differing on an equal value is
// username-reassignment evidence, not a rename of THIS account. There is
// no other Haven person to name, so this mirrors how that branch names the
// owner: personId/name point back at the person being edited.
test("editPerson refuses an equal-value submission whose platformId disagrees with the one already proven", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const id = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai Tran",
      normalizedName: "mai tran",
      contactHandles: [
        { platform: "x", value: "mai", source: "proven", platformId: "id-old" },
      ],
      updatedAt: Date.now(),
    }),
  );
  const before = await t.run((ctx) => ctx.db.get("people", id));

  const result = await as.mutation(api.people.editPerson, {
    id,
    contactHandles: [
      { platform: "x", value: "mai", platformId: "id-new" },
    ],
  });

  expect(result).toEqual({
    status: "handle_taken",
    personId: id,
    name: "Mai Tran",
  });
  // Zero writes: the proven id stays exactly what it was.
  const after = await t.run((ctx) => ctx.db.get("people", id));
  expect(after).toEqual(before);
});

test("editPerson allows re-submitting the exact same platformId on an equal value", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const id = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai Tran",
      normalizedName: "mai tran",
      contactHandles: [
        { platform: "x", value: "mai", source: "proven", platformId: "id-old" },
      ],
      updatedAt: Date.now(),
    }),
  );

  const edited = await editPersonOk(as, {
    id,
    contactHandles: [{ platform: "x", value: "mai", platformId: "id-old" }],
  });

  expect(edited.contactHandles?.[0].platformId).toBe("id-old");
});

test("editPerson still carries forward the proven platformId when the submission sends none at all", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const id = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai Tran",
      normalizedName: "mai tran",
      contactHandles: [
        { platform: "x", value: "mai", source: "proven", platformId: "id-old" },
      ],
      updatedAt: Date.now(),
    }),
  );

  // The S1 carry-forward case, unaffected: a client that only reordered the
  // handles list, or resubmitted a bare {platform, value}, sends no
  // platformId at all -- that must keep carrying the proven one forward,
  // not read as a claim that disagrees with it.
  const edited = await editPersonOk(as, {
    id,
    contactHandles: [{ platform: "x", value: "mai" }],
  });

  expect(edited.contactHandles?.[0].platformId).toBe("id-old");
});

test("saveSharedProfile follows a rename: a re-share under the same platformId updates the stored handle", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const first = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "old.username",
    profileUrl: "https://instagram.com/old.username",
    name: "Mai Tran",
    platformId: "ig-12345",
  });
  expect(first.status).toBe("created");
  const before = await as.query(api.people.getPerson, { id: first.personId });
  const originalAddedAt = before?.contactHandles?.[0]?.addedAt;
  expect(typeof originalAddedAt).toBe("number");

  // Later, the same account shared again under its new username: valueKey
  // alone would read this as a different account entirely, but platformId
  // proves it is still Mai.
  const second = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "new.username",
    profileUrl: "https://instagram.com/new.username",
    name: "Mai Tran",
    platformId: "ig-12345",
  });
  expect(second.status).toBe("already");
  expect(second.personId).toBe(first.personId);

  // The rename-following behavior the product wants: the display follows
  // the account's current name, and addedAt is preserved rather than reset
  // -- the account has been known since the original share, only its name
  // changed.
  const person = await as.query(api.people.getPerson, { id: first.personId });
  expect(person?.contactHandles).toEqual([
    {
      platform: "instagram",
      value: "new.username",
      platformId: "ig-12345",
      addedAt: originalAddedAt,
    },
  ]);
  const rows = await t.run((ctx) =>
    ctx.db
      .query("personHandles")
      .withIndex("by_person", (q) => q.eq("personId", first.personId))
      .collect(),
  );
  expect(rows).toHaveLength(1);
  expect(rows[0].valueKey).toBe("new.username");
  expect(rows[0].platformId).toBe("ig-12345");
});

// R3: an equal-value save used to discard a newly resolved platformId
// outright -- the exact-match branch in mergeHandleIntoOwner treated "same
// value" as "nothing to do" and never looked at whether this submission
// carried an id the stored handle lacked. That is the whole chain
// rename-proofing depends on: without the enrichment, a handle saved before
// its platformId was ever resolved can NEVER become id-findable, so a later
// rename (a genuinely different valueKey) has nothing to match by id and
// mints a twin instead of updating the one person who already exists.
test("saveSharedProfile enriches a handle with a resolved platformId on an equal-value re-share, so a later rename still finds the same person", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);

  // 1. Saved with no id at all -- a typed handle, or a share from before
  // ids were resolved.
  const first = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "mai.makes",
    profileUrl: "https://instagram.com/mai.makes",
    name: "Mai Tran",
  });
  expect(first.status).toBe("created");
  const before = await as.query(api.people.getPerson, { id: first.personId });
  const originalAddedAt = before?.contactHandles?.[0]?.addedAt;
  expect(typeof originalAddedAt).toBe("number");

  // 2. Same exact value re-shared, but this time an id was resolved. The
  // value alone already matches this person -- the enrichment is the only
  // thing that has to happen here.
  const second = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "mai.makes",
    profileUrl: "https://instagram.com/mai.makes",
    name: "Mai Tran",
    platformId: "ig-123",
  });
  expect(second.status).toBe("already");
  expect(second.personId).toBe(first.personId);

  const enriched = await as.query(api.people.getPerson, { id: first.personId });
  expect(enriched?.contactHandles).toEqual([
    {
      platform: "instagram",
      value: "mai.makes",
      platformId: "ig-123",
      addedAt: originalAddedAt,
    },
  ]);

  // 3. A later share under a renamed value, carrying the same id: this can
  // only attach to the same person if step 2 actually stored the id.
  const third = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "mai.renamed",
    profileUrl: "https://instagram.com/mai.renamed",
    name: "Mai Tran",
    platformId: "ig-123",
  });
  expect(third.status).toBe("already");
  expect(third.personId).toBe(first.personId);

  const renamed = await as.query(api.people.getPerson, { id: first.personId });
  expect(renamed?.contactHandles).toEqual([
    {
      platform: "instagram",
      value: "mai.renamed",
      platformId: "ig-123",
      addedAt: originalAddedAt,
    },
  ]);

  // No twin ever existed.
  const all = await t.run((ctx) =>
    ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect(),
  );
  expect(all).toHaveLength(1);
});

// The id-preferred merge bug: A owns {value:"old", platformId:"id-a"}; B
// separately owns {value:"new"} (no platformId). A share of {value:"new",
// platformId:"id-a"} finds A by id and, unguarded, would rewrite A's value
// to "new" -- double-indexing "new" onto two different people's rows. Fixed
// by refusing the rename when the incoming valueKey already belongs to
// somebody else: zero-guess doctrine, nothing written for that handle.
test("saveSharedProfile refuses an id-preferred rename onto a value someone else already owns", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);

  const b = await as.mutation(api.people.addPersonWithOutcome, {
    name: "New Person",
    context: "met at the market",
    contactHandles: [{ platform: "instagram", value: "new.username" }],
  });
  if (b.status !== "created") throw new Error("unreachable");
  const a = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "gave me her card",
    contactHandles: [
      { platform: "instagram", value: "old.username", platformId: "ig-12345" },
    ],
  });
  if (a.status !== "created") throw new Error("unreachable");

  const result = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "new.username",
    profileUrl: "https://instagram.com/new.username",
    name: "Mai Tran",
    platformId: "ig-12345",
  });

  expect(result).toEqual({
    status: "conflict",
    personId: a.personId,
    noteTruncated: false,
    handleDropped: false,
    conflictPersonId: b.personId,
  });

  // Neither person's handle moved.
  const aAfter = await as.query(api.people.getPerson, { id: a.personId });
  expect(displayOnly(aAfter?.contactHandles)).toEqual([
    { platform: "instagram", value: "old.username" },
  ]);
  const bAfter = await as.query(api.people.getPerson, { id: b.personId });
  expect(displayOnly(bAfter?.contactHandles)).toEqual([
    { platform: "instagram", value: "new.username" },
  ]);
  // "new.username" still indexes to exactly one person (B), not two.
  const owners = await t.run((ctx) =>
    ctx.db
      .query("personHandles")
      .withIndex("by_user_and_platform_and_valueKey", (q) =>
        q.eq("userId", userId).eq("platform", "instagram").eq("valueKey", "new.username"),
      )
      .collect(),
  );
  expect(owners.map((row) => row.personId)).toEqual([b.personId]);
});

// X1: username reassignment. The old owner of "mai" renamed away or was
// never re-shared since; the stored row still says mai/id-old. A NEW human
// has since claimed the bare username "mai" on the platform, and shares
// under mai/id-new. findHandleOwner has no id-new on file yet, so it falls
// through to the plain value lookup and finds the OLD person by "mai" alone
// -- the equal-value branch used to read that as "nothing to do" and
// silently attached the new human's note to the old, wrong person. The ids
// disagreeing is proof this is not the same account; refuse rather than
// guess.
test("saveSharedProfile refuses an equal-username share whose platformId disagrees with the stored one", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const oldOwner = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "gave me her card",
    contactHandles: [
      { platform: "instagram", value: "mai", platformId: "id-old" },
    ],
  });
  if (oldOwner.status !== "created") throw new Error("unreachable");
  const before = await t.run((ctx) => ctx.db.get("people", oldOwner.personId));

  const result = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "mai",
    profileUrl: "https://instagram.com/mai",
    name: "A Stranger",
    platformId: "id-new",
  });

  expect(result.status).toBe("conflict");
  if (result.status !== "conflict") throw new Error("unreachable");
  expect(result.personId).toBe(oldOwner.personId);

  // Zero writes: the old owner's row, its handle, and the index are all
  // untouched -- not renamed to "A Stranger", not re-stamped with id-new.
  const after = await t.run((ctx) => ctx.db.get("people", oldOwner.personId));
  expect(after).toEqual(before);
  const rows = await t.run((ctx) =>
    ctx.db
      .query("personHandles")
      .withIndex("by_person", (q) => q.eq("personId", oldOwner.personId))
      .collect(),
  );
  expect(rows).toMatchObject([{ valueKey: "mai", platformId: "id-old" }]);
  // No second person was minted for "A Stranger" either -- refused, not
  // silently created as a fallback.
  const everyone = await t.run((ctx) =>
    ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", before!.userId))
      .collect(),
  );
  expect(everyone).toHaveLength(1);
});

test("addPerson refuses an id-preferred rename onto a value someone else already owns", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const b = await as.mutation(api.people.addPersonWithOutcome, {
    name: "New Person",
    context: "met at the market",
    contactHandles: [{ platform: "instagram", value: "new.username" }],
  });
  if (b.status !== "created") throw new Error("unreachable");
  const a = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "gave me her card",
    contactHandles: [
      { platform: "instagram", value: "old.username", platformId: "ig-12345" },
    ],
  });
  if (a.status !== "created") throw new Error("unreachable");

  const result = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "saw her new handle",
    contactHandles: [
      { platform: "instagram", value: "new.username", platformId: "ig-12345" },
    ],
  });

  expect(result.status).toBe("conflict");
  if (result.status !== "conflict") throw new Error("unreachable");
  expect(new Set(result.personIds)).toEqual(new Set([a.personId, b.personId]));

  const aAfter = await as.query(api.people.getPerson, { id: a.personId });
  expect(displayOnly(aAfter?.contactHandles)).toEqual([
    { platform: "instagram", value: "old.username" },
  ]);
});

// S2: the X-rename resolution happens AFTER the save, so the id-first dedup
// never sees it at write time -- patchXPlatformId is the write path, and it
// has to refuse rather than stamp a second person with an id another one of
// this user's people already owns.
test("patchXPlatformId refuses to stamp a platformId a different person already owns", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const a = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Tony A",
    context: "met at the demo day",
    contactHandles: [{ platform: "x", value: "tony-a", platformId: "x-id-1" }],
  });
  if (a.status !== "created") throw new Error("unreachable");
  const b = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Tony B",
    context: "met at a different demo day",
    contactHandles: [{ platform: "x", value: "tony-b" }],
  });
  if (b.status !== "created") throw new Error("unreachable");

  const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
  // No userId argument (Standards 1): the caller's identity comes from the
  // same withIdentity() session addPerson above used, the same way
  // resolveXPlatformId's own requireUser call feeds this internal mutation
  // in production.
  await as.mutation(internal.people.patchXPlatformId, {
    personId: b.personId,
    username: "tony-b",
    platformId: "x-id-1",
  });
  // Checked before restoring: mockRestore also clears the recorded calls,
  // so asserting on them has to happen while the spy is still live.
  expect(errorSpy).toHaveBeenCalled();
  // Redacted: the log names ids, never the platformId or username itself.
  const logged = errorSpy.mock.calls.map((call) => call.join(" ")).join("\n");
  expect(logged).not.toContain("x-id-1");
  expect(logged).not.toContain("tony-b");
  errorSpy.mockRestore();

  // B never gained an id that already, provably, names A.
  const bAfter = await as.query(api.people.getPerson, { id: b.personId });
  expect(bAfter?.contactHandles?.[0]).not.toHaveProperty("platformId");
  const aAfter = await as.query(api.people.getPerson, { id: a.personId });
  expect(aAfter?.contactHandles?.[0].platformId).toBe("x-id-1");
});

// W3: same shape as W2's editPerson guard and mergeHandleIntoOwner's X1
// rule, on the one write path that goes through neither -- the username
// still matches (so the value check above lets this through), but Composio
// resolved a DIFFERENT id than what this handle already had proven. A
// disagreeing id is evidence of username reassignment, not confirmation of
// the same account; findHandleOwner's own lookup for "does somebody ELSE
// own this id" finds nobody (id-new is unclaimed) and would otherwise let
// the overwrite through silently.
test("patchXPlatformId no-ops when the resolved id disagrees with the one already proven", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const a = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "gave me her card",
    contactHandles: [
      { platform: "x", value: "mai", platformId: "id-old" },
    ],
  });
  if (a.status !== "created") throw new Error("unreachable");

  const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
  await as.mutation(internal.people.patchXPlatformId, {
    personId: a.personId,
    username: "mai",
    platformId: "id-new",
  });
  expect(errorSpy).toHaveBeenCalled();
  const logged = errorSpy.mock.calls.map((call) => call.join(" ")).join("\n");
  expect(logged).not.toContain("id-old");
  expect(logged).not.toContain("id-new");
  expect(logged).not.toContain("mai");
  errorSpy.mockRestore();

  const after = await as.query(api.people.getPerson, { id: a.personId });
  expect(after?.contactHandles?.[0].platformId).toBe("id-old");
});

// The one person who legitimately DOES already own that id gets the write:
// re-resolving the same account's id (a retried action, a second save) is
// an idempotent no-op, not a refusal.
test("patchXPlatformId allows re-stamping the same id onto the person who already owns it", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const a = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Tony A",
    context: "met at the demo day",
    contactHandles: [{ platform: "x", value: "tony-a", platformId: "x-id-1" }],
  });
  if (a.status !== "created") throw new Error("unreachable");

  await as.mutation(internal.people.patchXPlatformId, {
    personId: a.personId,
    username: "tony-a",
    platformId: "x-id-1",
  });

  const after = await as.query(api.people.getPerson, { id: a.personId });
  expect(after?.contactHandles?.[0].platformId).toBe("x-id-1");
});

// Standards 1: patchXPlatformId used to take a userId argument and trust it
// for the ownership check -- resolveXPlatformId always passed its own
// requireUser result, so nothing exploited this in practice, but the
// argument was the ONLY thing standing in the way of a different caller
// stamping an id onto somebody else's person. There is no argument to spoof
// anymore: this proves the ownership check runs against the mutation's own
// caller, not a value anyone passed in.
test("patchXPlatformId authorizes against the caller's own identity, not any argument", async () => {
  const t = convexTest(schema, modules);
  const owner = await asNewUser(t);
  const other = await asNewUser(t);
  const person = await owner.as.mutation(api.people.addPersonWithOutcome, {
    name: "Tony A",
    context: "met at the demo day",
    contactHandles: [{ platform: "x", value: "tony-a" }],
  });
  if (person.status !== "created") throw new Error("unreachable");

  // `other` calls this as themselves -- there is no userId field left to
  // claim to be `owner` with.
  await other.as.mutation(internal.people.patchXPlatformId, {
    personId: person.personId,
    username: "tony-a",
    platformId: "x-id-1",
  });

  const after = await owner.as.query(api.people.getPerson, { id: person.personId });
  expect(after?.contactHandles?.[0]).not.toHaveProperty("platformId");
});

test("addPerson prefers platformId over valueKey when both are present", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const owner = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "gave me her card",
    contactHandles: [
      { platform: "instagram", value: "old.username", platformId: "ig-1" },
    ],
  });
  if (owner.status !== "created") throw new Error("unreachable");

  // A totally different valueKey would not match on its own; platformId is
  // what proves this is the same account.
  const result = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai (new handle)",
    context: "she changed her Instagram name",
    contactHandles: [
      { platform: "instagram", value: "brand.new.username", platformId: "ig-1" },
    ],
  });
  expect(result.status).toBe("attached");
  if (result.status !== "attached") throw new Error("unreachable");
  expect(result.personId).toBe(owner.personId);
});

test("addPerson signals a dropped handle when the owner is already at the 8-handle cap", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const eightHandles = Array.from({ length: 8 }, (_, i) => ({
    platform: `platform${i}`,
    value: `v${i}`,
  }));
  const owner = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "met her",
    contactHandles: eightHandles,
  });
  if (owner.status !== "created") throw new Error("unreachable");

  const result = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai (again)",
    context: "ran into her again, she gave me her Instagram too",
    contactHandles: [
      { platform: "platform0", value: "v0" },
      { platform: "instagram", value: "mai.makes" },
    ],
  });
  expect(result.status).toBe("attached");
  if (result.status !== "attached") throw new Error("unreachable");
  expect(result.handleDropped).toBe(true);

  const person = await as.query(api.people.getPerson, { id: owner.personId });
  expect(person?.contactHandles).toHaveLength(8);
  expect(
    person?.contactHandles?.some((handle) => handle.platform === "instagram"),
  ).toBe(false);
});

test("addPerson attach signals a truncated note", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const owner = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "x".repeat(3990),
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });
  if (owner.status !== "created") throw new Error("unreachable");

  const result = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai (again)",
    context: "y".repeat(300),
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });
  expect(result.status).toBe("attached");
  if (result.status !== "attached") throw new Error("unreachable");
  expect(result.noteTruncated).toBe(true);

  const person = await as.query(api.people.getPerson, { id: owner.personId });
  expect(person?.context).toHaveLength(4000);
});

test("addPerson stores contact handles and a preferred platform", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const id = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tran",
    // Free-form platforms on purpose: a saved person can carry any way to
    // reach them, not just the four platforms of your own card.
    contactHandles: [
      { platform: " Instagram ", value: "mai.makes" },
      { platform: "whatsapp", value: "+84 90 123 4567" },
    ],
    preferredPlatform: "WhatsApp",
  });

  const person = await as.query(api.people.getPerson, { id });
  expect(displayOnly(person?.contactHandles)).toEqual([
    { platform: "instagram", value: "mai.makes" },
    { platform: "whatsapp", value: "+84 90 123 4567" },
  ]);
  expect(person?.preferredPlatform).toBe("whatsapp");
});

test("addPerson rejects bad handle lists", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  // Case-differing duplicates are still duplicates: uniqueness runs on the
  // normalized platform, which is also what the preferred pointer matches.
  await expect(
    as.mutation(api.people.addPersonWithOutcome, {
      ...manualAdd,
      name: "Mai",
      contactHandles: [
        { platform: "Instagram", value: "a" },
        { platform: "instagram", value: "b" },
      ],
    }),
  ).rejects.toThrow("Keep one handle per platform");

  await expect(
    as.mutation(api.people.addPersonWithOutcome, {
      ...manualAdd,
      name: "Mai",
      contactHandles: [{ platform: "instagram", value: "a" }],
      preferredPlatform: "telegram",
    }),
  ).rejects.toThrow("Choose a preferred platform you have a handle for");

  await expect(
    as.mutation(api.people.addPersonWithOutcome, {
      ...manualAdd,
      name: "Mai",
      contactHandles: Array.from({ length: 9 }, (_, i) => ({
        platform: `platform${i}`,
        value: "x",
      })),
    }),
  ).rejects.toThrow("Keep at most 8 contact handles");
});

// The reviewer's exact scenario (identity brief, R1): a phone/whatsapp value
// with no digit at all folds through handleValueKey's own lowercase
// fallback, so "unknown" and "Unknown" from two different strangers would
// otherwise collide on the same personHandles row. Refusing the value at the
// write gate, rather than letting it fold, is what keeps that from merging
// two unrelated people.
test("addPerson rejects a phone or whatsapp value with no digit at all", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  await expect(
    as.mutation(api.people.addPersonWithOutcome, {
      name: "Alice",
      contactHandles: [{ platform: "phone", value: "unknown" }],
      context: "met at a party",
    }),
  ).rejects.toThrow("A phone number needs at least one digit");

  await expect(
    as.mutation(api.people.addPersonWithOutcome, {
      name: "Alice",
      contactHandles: [{ platform: "whatsapp", value: "ask mai" }],
      context: "met at a party",
    }),
  ).rejects.toThrow("A phone number needs at least one digit");
});

test("editPerson rejects a phone value with no digit at all", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await addPersonId(as, { ...manualAdd, name: "Alice" });

  await expect(
    as.mutation(api.people.editPerson, {
      id,
      contactHandles: [{ platform: "phone", value: "unknown" }],
    }),
  ).rejects.toThrow("A phone number needs at least one digit");
});

// -------------------------------------------------------------- contact photo

// convex-test's storage mock drops the Blob's contentType, so photo
// validation would always see undefined. Patch the system table directly --
// same workaround as profiles.test.ts and captures.test.ts.
async function seedPhoto(
  t: ReturnType<typeof convexTest>,
  contentType = "image/jpeg",
) {
  const id = await t.run((ctx) =>
    ctx.storage.store(new Blob(["fake-photo"], { type: contentType })),
  );
  await t.run((ctx) => (ctx.db as any).patch("_storage", id, { contentType }));
  return id;
}

test("addPerson stores a photo and getPerson returns a photo url", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const photoStorageId = await seedPhoto(t);

  const id = await addPersonId(as, {
    ...manualAdd,
    name: "Mai",
    photoStorageId,
  });
  const person = await as.query(api.people.getPerson, { id });
  expect(person?.photoUrl).toEqual(expect.any(String));

  // A person without a photo answers null, so the client never guesses.
  const bareId = await addPersonId(as, { ...manualAdd, name: "Vy" });
  const bare = await as.query(api.people.getPerson, { id: bareId });
  expect(bare?.photoUrl).toBeNull();
});

test("addPerson rejects a non-image photo without writing a person", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const blobId = await seedPhoto(t, "text/plain");

  await expect(
    as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Mai", photoStorageId: blobId }),
  ).rejects.toThrow("Please choose an image under 10 MB");

  // The throw rolled the person insert back. The stray blob is the orphan
  // sweep's job: a throwing mutation cannot delete storage, because the
  // delete rolls back with everything else.
  const people = await t.run((ctx) => ctx.db.query("people").collect());
  expect(people).toHaveLength(0);
});

// ----------------------------------------------------------------- editPerson

test("editPerson patches provided fields, clears on null, leaves the rest", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tran",
    context: "met at the coffee meetup",
    company: "LinkedIn",
    city: { name: "Da Nang" },
  });

  vi.advanceTimersByTime(1000);
  const before = await t.run((ctx) => ctx.db.get("people", id));

  const edited = await editPersonOk(as, {
    id,
    role: "Recruiter",
    company: null,
  });

  // role arrived, company cleared, everything omitted stayed put.
  expect(edited.role).toBe("Recruiter");
  expect(edited.company).toBeUndefined();
  expect(edited.context).toBe("met at the coffee meetup");
  expect(edited.city).toEqual({ name: "Da Nang" });
  expect(edited.updatedAt).toBeGreaterThan(before!.updatedAt);

  // The derived key clears with its display value, or the chip filter would
  // keep matching a company the card no longer shows.
  const stored = await t.run((ctx) => ctx.db.get("people", id));
  expect(stored?.companyKey).toBeUndefined();
  expect(stored?.roleKey).toBe("recruiter");
});

test("editPerson renames a person and search finds the new name", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await addPersonId(as, { ...manualAdd, name: "Maya Chen" });

  await as.mutation(api.people.editPerson, {
    id,
    name: "Nguy\u1ec5n V\u0103n D\u0169ng",
  });

  const hits = await as.query(api.people.searchPeople, { query: "dung" });
  expect(hits.map((p) => p.name)).toEqual(["Nguy\u1ec5n V\u0103n D\u0169ng"]);
  expect(
    await as.query(api.people.searchPeople, { query: "Maya" }),
  ).toHaveLength(0);
});

test("editPerson rejects a blank name and never clears it", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await addPersonId(as, { ...manualAdd, name: "Mai" });
  await expect(
    as.mutation(api.people.editPerson, { id, name: "  " }),
  ).rejects.toThrow("Name is required");
});

test("editPerson keeps the preferred pointer consistent with the handles", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await addPersonId(as, {
    ...manualAdd,
    name: "Mai",
    contactHandles: [
      { platform: "instagram", value: "mai.makes" },
      { platform: "whatsapp", value: "+84 90 123 4567" },
    ],
    preferredPlatform: "whatsapp",
  });

  // Replacing the list without the preferred platform clears the pointer
  // instead of dangling it.
  const afterDrop = await editPersonOk(as, {
    id,
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });
  expect(afterDrop.preferredPlatform).toBeUndefined();

  // Choosing a preferred platform that has no handle is refused.
  await expect(
    as.mutation(api.people.editPerson, { id, preferredPlatform: "telegram" }),
  ).rejects.toThrow("Choose a preferred platform you have a handle for");

  const afterPick = await editPersonOk(as, {
    id,
    preferredPlatform: "Instagram",
  });
  expect(afterPick.preferredPlatform).toBe("instagram");
});

test("editPerson swaps the photo and deletes the replaced blob", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const firstPhoto = await seedPhoto(t);
  const id = await addPersonId(as, {
    ...manualAdd,
    name: "Mai",
    photoStorageId: firstPhoto,
  });

  const secondPhoto = await seedPhoto(t);
  const swapped = await editPersonOk(as, {
    id,
    photoStorageId: secondPhoto,
  });
  expect(swapped.photoUrl).toEqual(expect.any(String));
  // The replaced blob is gone for good -- this commit path CAN delete.
  expect(
    await t.run((ctx) => ctx.db.system.get("_storage", firstPhoto)),
  ).toBeNull();

  // Clearing the photo also deletes the blob it dereferences.
  const cleared = await editPersonOk(as, {
    id,
    photoStorageId: null,
  });
  expect(cleared.photoUrl).toBeNull();
  expect(
    await t.run((ctx) => ctx.db.system.get("_storage", secondPhoto)),
  ).toBeNull();
});

test("deletePerson also removes the photo blob", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const photoStorageId = await seedPhoto(t);
  const id = await addPersonId(as, {
    ...manualAdd,
    name: "Mai",
    photoStorageId,
  });

  await as.mutation(api.people.deletePerson, { personId: id });

  expect(
    await t.run((ctx) => ctx.db.system.get("_storage", photoStorageId)),
  ).toBeNull();
});

// ------------------------------------------------------------------ directory

test("listPeople pages the caller's directory, most recently touched first", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  const a = await addPersonId(me.as, { ...manualAdd, name: "An" });
  vi.advanceTimersByTime(1000);
  await me.as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Binh" });
  vi.advanceTimersByTime(1000);
  await me.as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Chi" });
  await other.as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Rao" });

  // Editing An bumps them to the top: recency means last touched, not first
  // created, which is what keeps the screen useful after months of use.
  vi.advanceTimersByTime(1000);
  await me.as.mutation(api.people.editPerson, { id: a, context: "met again" });

  const page1 = await me.as.query(api.people.listPeople, {
    paginationOpts: { numItems: 2, cursor: null },
  });
  expect(page1.page.map((p) => p.name)).toEqual(["An", "Chi"]);
  expect(page1.isDone).toBe(false);

  const page2 = await me.as.query(api.people.listPeople, {
    paginationOpts: { numItems: 2, cursor: page1.continueCursor },
  });
  expect(page2.page.map((p) => p.name)).toEqual(["Binh"]);
  expect(page2.isDone).toBe(true);

  await expect(
    t.query(api.people.listPeople, {
      paginationOpts: { numItems: 1, cursor: null },
    }),
  ).rejects.toThrow("Not signed in");
});

// ------------------------------------------- MVP search contract (Phase 3)

test("searchDirectory finds people by note keywords, scoped to the caller", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  await me.as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "An Vo",
    context: "wore a Spain shirt, works on the research team, talked soccer",
    company: "Amazon",
  });
  await me.as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "Binh Le",
    context: "recruiter, met at the rooftop mixer",
    company: "LinkedIn",
  });
  // Same keyword in another user's note must never surface here.
  await other.as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "Rao",
    context: "planning a Spain trip",
  });

  const hits = await me.as.query(api.people.searchDirectory, {
    keyword: "spain",
  });
  expect(hits.map((p) => p.name)).toEqual(["An Vo"]);
});

test("searchDirectory combines a keyword with chip filters", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  await as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "An Vo",
    context: "talked soccer at the meetup",
    company: "Amazon",
  });
  await as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "Binh Le",
    context: "talked soccer over coffee",
    company: "LinkedIn",
  });

  const both = await as.query(api.people.searchDirectory, {
    keyword: "soccer",
  });
  expect(both.map((p) => p.name).sort()).toEqual(["An Vo", "Binh Le"]);

  const chipped = await as.query(api.people.searchDirectory, {
    keyword: "soccer",
    company: "amazon",
  });
  expect(chipped.map((p) => p.name)).toEqual(["An Vo"]);

  const none = await as.query(api.people.searchDirectory, {
    keyword: "soccer",
    company: "Photon",
  });
  expect(none).toEqual([]);
});

test("searchDirectory filters by chips alone, accent-insensitively", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  await as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "An Vo",
    company: "LinkedIn",
    city: { name: "San Francisco" },
  });
  await as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "Binh Le",
    company: "LinkedIn",
    role: "Recruiter",
    city: { name: "S\u00e0i G\u00f2n" },
  });

  const company = await as.query(api.people.searchDirectory, {
    company: "linkedin",
  });
  expect(company.map((p) => p.name).sort()).toEqual(["An Vo", "Binh Le"]);

  // The accented stored city matches the plain-typed chip, same folding as
  // name search.
  const city = await as.query(api.people.searchDirectory, {
    company: "LinkedIn",
    city: "sai gon",
  });
  expect(city.map((p) => p.name)).toEqual(["Binh Le"]);

  const role = await as.query(api.people.searchDirectory, { role: "recruiter" });
  expect(role.map((p) => p.name)).toEqual(["Binh Le"]);

  const miss = await as.query(api.people.searchDirectory, {
    company: "LinkedIn",
    city: "Da Nang",
  });
  expect(miss).toEqual([]);
});

test("searchDirectory with no keyword and no chips returns recent people", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "An" });
  vi.advanceTimersByTime(1000);
  await as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "Binh" });

  const hits = await as.query(api.people.searchDirectory, {});
  expect(hits.map((p) => p.name)).toEqual(["Binh", "An"]);
});

test("searchDirectory keyword also matches names and card text", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "Nguy\u1ec5n V\u0103n D\u0169ng",
    company: "Photon",
  });

  // The contract promises notes; matching the rest of the card is a strict
  // superset that keeps one search box honest.
  const byName = await as.query(api.people.searchDirectory, {
    keyword: "dung",
  });
  expect(byName.map((p) => p.name)).toEqual(["Nguy\u1ec5n V\u0103n D\u0169ng"]);

  const byCompany = await as.query(api.people.searchDirectory, {
    keyword: "photon",
  });
  expect(byCompany).toHaveLength(1);
});

test("backfillSearchText patches legacy rows so keyword search finds them", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  // A row from before searchText existed, inserted raw like a legacy write.
  await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Ada Lovelace",
      normalizedName: "ada lovelace",
      context: "compiler engineer, met at the analytical engines meetup",
      updatedAt: Date.now(),
    }),
  );

  // No pre-backfill query here: convex-test crashes iterating a search
  // index over a row whose search field is missing, where real Convex just
  // leaves the row out of the index. The patched count proves targeting.
  const patched = await t.mutation(internal.people.backfillSearchText, {});
  expect(patched).toBe(1);

  const hits = await as.query(api.people.searchDirectory, {
    keyword: "compiler",
  });
  expect(hits.map((p) => p.name)).toEqual(["Ada Lovelace"]);

  // A second run finds nothing left to patch.
  expect(await t.mutation(internal.people.backfillSearchText, {})).toBe(0);
});

test("directoryFacets lists the caller's chip values with counts", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  await me.as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "A",
    company: "LinkedIn",
    city: { name: "S\u00e0i G\u00f2n" },
  });
  vi.advanceTimersByTime(1000);
  await me.as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "B",
    company: "linkedin",
    role: "Recruiter",
  });
  vi.advanceTimersByTime(1000);
  await me.as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "C",
    company: "Amazon",
    city: { name: "Sai Gon" },
  });
  await other.as.mutation(api.people.addPersonWithOutcome, { ...manualAdd, name: "D", company: "Photon" });

  const facets = await me.as.query(api.people.directoryFacets, {});

  // Case and accent variants collapse into one chip; the most recently used
  // spelling is the label; bigger groups list first. Another user's values
  // never appear.
  expect(facets.companies).toEqual([
    { value: "linkedin", count: 2 },
    { value: "Amazon", count: 1 },
  ]);
  expect(facets.cities).toEqual([{ value: "Sai Gon", count: 2 }]);
  expect(facets.roles).toEqual([{ value: "Recruiter", count: 1 }]);
});

test("searchDirectory reflects edits immediately", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await addPersonId(as, {
    ...manualAdd,
    name: "An",
    context: "met at the soccer game",
  });

  await as.mutation(api.people.editPerson, {
    id,
    context: "runs a pho place in district 3",
  });

  expect(
    await as.query(api.people.searchDirectory, { keyword: "soccer" }),
  ).toEqual([]);
  expect(
    (await as.query(api.people.searchDirectory, { keyword: "pho" })).map(
      (p) => p.name,
    ),
  ).toEqual(["An"]);
});

test("editPerson enforces ownership, auth, and the context cap", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  const otherId = await addPersonId(other.as, { ...manualAdd, name: "Rao" });

  await expect(
    me.as.mutation(api.people.editPerson, { id: otherId, context: "x" }),
  ).rejects.toThrow("Person not found");
  await expect(
    t.mutation(api.people.editPerson, { id: otherId, context: "x" }),
  ).rejects.toThrow("Not signed in");

  const myId = await addPersonId(me.as, { ...manualAdd, name: "Mai" });
  await expect(
    me.as.mutation(api.people.editPerson, {
      id: myId,
      context: "x".repeat(4001),
    }),
  ).rejects.toThrow("Context is too long");
});

// ------------------------------------------------- shared profile capture

// The share sheet's payload for a person the user just met on a platform.
const sharedProfile = {
  platform: "Instagram",
  handleValue: "mai.makes",
  profileUrl: "https://instagram.com/mai.makes",
  name: "Mai Tr\u1ea7n",
};

test("saveSharedProfile creates a person searchable by their handle", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const result = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    name: "  Mai Tr\u1ea7n  ",
    note: "met at the ceramics market",
  });
  expect(result.status).toBe("created");

  const person = await as.query(api.people.getPerson, { id: result.personId });
  expect(person?.name).toBe("Mai Tr\u1ea7n");
  expect(person?.link).toBe("https://instagram.com/mai.makes");
  expect(displayOnly(person?.contactHandles)).toEqual([
    { platform: "instagram", value: "mai.makes" },
  ]);
  expect(person?.context).toBe("met at the ceramics market");
  // Nothing is preferred until the user says so.
  expect(person?.preferredPlatform).toBeUndefined();

  const hits = await as.query(api.people.searchDirectory, {
    keyword: "mai.makes",
  });
  expect(hits.map((p) => p.name)).toEqual(["Mai Tr\u1ea7n"]);
});

test("saveSharedProfile re-shared with a new note appends instead of twinning", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const first = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    note: "makes ceramics",
  });
  vi.advanceTimersByTime(1000);
  const before = await t.run((ctx) => ctx.db.get("people", first.personId));

  // Same account, typed the way a share sheet actually hands it over.
  const again = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    handleValue: " @Mai.Makes ",
    note: "wants a studio in district 3",
  });
  expect(again).toEqual({ status: "already", personId: first.personId, noteTruncated: false, handleDropped: false });

  const people = await as.query(api.people.searchDirectory, {});
  expect(people).toHaveLength(1);

  const after = await t.run((ctx) => ctx.db.get("people", first.personId));
  expect(after?.context).toBe(
    "makes ceramics\nwants a studio in district 3",
  );
  expect(after!.updatedAt).toBeGreaterThan(before!.updatedAt);

  // Both notes stay searchable, which is the point of appending.
  for (const keyword of ["ceramics", "studio"]) {
    const hits = await as.query(api.people.searchDirectory, { keyword });
    expect(hits.map((p) => p._id)).toEqual([first.personId]);
  }
});

test("saveSharedProfile attaches a second platform to the person the user picked", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tr\u1ea7n",
    context: "met at the ceramics market",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });

  const result = await as.mutation(api.people.saveSharedProfile, {
    platform: "linkedin",
    handleValue: "mai-tran-8a91b2",
    profileUrl: "https://www.linkedin.com/in/mai-tran-8a91b2",
    name: "Mai Tran",
    note: "leads design at Photon",
    attachToPersonId: personId,
  });
  expect(result).toEqual({ status: "attached", personId, noteTruncated: false, handleDropped: false });

  const person = await as.query(api.people.getPerson, { id: personId });
  expect(displayOnly(person?.contactHandles)).toEqual([
    { platform: "instagram", value: "mai.makes" },
    { platform: "linkedin", value: "mai-tran-8a91b2" },
  ]);
  expect(person?.context).toBe(
    "met at the ceramics market\nleads design at Photon",
  );

  // The new handle joins the haystack and the identity index at once.
  const hits = await as.query(api.people.searchDirectory, {
    keyword: "mai-tran-8a91b2",
  });
  expect(hits.map((p) => p._id)).toEqual([personId]);
  const dedup = await as.mutation(api.people.saveSharedProfile, {
    platform: "LinkedIn",
    handleValue: "Mai-Tran-8A91B2",
    profileUrl: "https://linkedin.com/in/mai-tran-8a91b2",
    name: "Mai Tran",
  });
  expect(dedup).toEqual({ status: "already", personId, noteTruncated: false, handleDropped: false });
});

test("saveSharedProfile creates a new person when the attach target holds another handle on that platform", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tr\u1ea7n",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });

  // The drain replays this with nobody present to resolve the conflict, so
  // refusing would strand the capture; it lands as its own person instead.
  const result = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    handleValue: "mai.ceramics",
    profileUrl: "https://instagram.com/mai.ceramics",
    attachToPersonId: personId,
  });
  expect(result.status).toBe("created");
  expect(result.personId).not.toBe(personId);

  const target = await as.query(api.people.getPerson, { id: personId });
  expect(displayOnly(target?.contactHandles)).toEqual([
    { platform: "instagram", value: "mai.makes" },
  ]);
  const created = await as.query(api.people.getPerson, {
    id: result.personId,
  });
  expect(displayOnly(created?.contactHandles)).toEqual([
    { platform: "instagram", value: "mai.ceramics" },
  ]);
});

test("saveSharedProfile creates a person when the attach target is gone or not the caller's", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  // The extension's mirror can be days stale; a capture must never be lost.
  const deletedId = await addPersonId(me.as, { ...manualAdd, name: "Mai" });
  await me.as.mutation(api.people.deletePerson, { personId: deletedId });

  const fromDeleted = await me.as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    attachToPersonId: deletedId,
  });
  expect(fromDeleted.status).toBe("created");
  expect(fromDeleted.personId).not.toBe(deletedId);

  // Captured once: manualAdd.contactHandles is a getter that hands out a
  // fresh number per read (so two calls never collide on one identity, see
  // the fixture's own comment), so reading it again below for the assertion
  // would compare against a value nobody ever stored.
  const raosHandles = manualAdd.contactHandles;
  const theirId = await addPersonId(other.as, {
    ...manualAdd,
    name: "Rao",
    contactHandles: raosHandles,
  });
  const fromTheirs = await me.as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    handleValue: "mai.ceramics",
    profileUrl: "https://instagram.com/mai.ceramics",
    attachToPersonId: theirId,
  });
  expect(fromTheirs.status).toBe("created");
  expect(fromTheirs.personId).not.toBe(theirId);
  // The other user's person gained nothing from the capture.
  expect(
    displayOnly(
      (await other.as.query(api.people.getPerson, { id: theirId }))
        ?.contactHandles,
    ),
  ).toEqual(raosHandles);
});

test("saveSharedProfile refuses to steal a handle that already belongs to someone else", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const mai = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tr\u1ea7n",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });
  // Captured once: manualAdd.contactHandles is a getter that hands out a
  // fresh number per read, so reading it again below for the assertion would
  // compare against a value nobody stored on Binh.
  const binhsHandles = manualAdd.contactHandles;
  const binh = await addPersonId(as, {
    ...manualAdd,
    name: "Binh Le",
    contactHandles: binhsHandles,
  });

  // Binh was the caller's guess (e.g. a stale "same person?" pick), but this
  // handle is already, provably, Mai's -- the save must refuse rather than
  // silently land the note on whichever of the two the handle actually
  // names.
  const result = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    attachToPersonId: binh,
  });
  expect(result).toEqual({
    status: "conflict",
    personId: mai,
    noteTruncated: false,
    handleDropped: false,
    conflictPersonId: binh,
  });

  // Nothing was written anywhere: not the guess, not the true owner.
  expect(
    displayOnly(
      (await as.query(api.people.getPerson, { id: binh }))?.contactHandles,
    ),
  ).toEqual(binhsHandles);
  const maiAfter = await as.query(api.people.getPerson, { id: mai });
  expect(maiAfter?.context).toBe(manualAdd.context);
});

test("saveSharedProfile attaches onto a handle whose stored platform was never normalized", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  // Written before this index existed, so nothing folded its platform.
  const personId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai Tr\u1ea7n",
      normalizedName: "mai tran",
      contactHandles: [{ platform: "Instagram ", value: "mai.makes" }],
      updatedAt: Date.now(),
    }),
  );

  // Character-for-character the handle already on the row: re-sharing it must
  // not be mistaken for a second account and cost the user their note.
  const result = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    note: "met at the ceramics market",
    attachToPersonId: personId,
  });
  expect(result).toEqual({ status: "attached", personId, noteTruncated: false, handleDropped: false });

  const person = await as.query(api.people.getPerson, { id: personId });
  expect(person?.context).toBe("met at the ceramics market");
  expect(person?.contactHandles).toHaveLength(1);

  // A genuinely different account on that platform lands as its own person
  // rather than failing the queued capture.
  const second = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    handleValue: "mai.ceramics",
    profileUrl: "https://instagram.com/mai.ceramics",
    attachToPersonId: personId,
  });
  expect(second.status).toBe("created");
  expect(second.personId).not.toBe(personId);
});

test("saveSharedProfile clamps an over-cap note instead of failing the capture", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  // 4000 is the context cap. The drain replays a queued note long after the
  // sheet closed, so an overflow cannot ask the user; the capture keeps what
  // fits instead of failing forever.
  const big = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    note: "z".repeat(4200),
  });
  expect(big.status).toBe("created");
  expect(big.noteTruncated).toBe(true);
  const bigPerson = await as.query(api.people.getPerson, {
    id: big.personId,
  });
  expect(bigPerson?.context).toHaveLength(4000);

  const first = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    handleValue: "mai.ceramics",
    profileUrl: "https://instagram.com/mai.ceramics",
    note: "x".repeat(3900),
  });
  const again = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    handleValue: "mai.ceramics",
    profileUrl: "https://instagram.com/mai.ceramics",
    note: "y".repeat(300),
  });
  expect(again).toEqual({
    status: "already",
    personId: first.personId,
    noteTruncated: true,
    handleDropped: false,
  });
  const person = await as.query(api.people.getPerson, {
    id: first.personId,
  });
  // The existing context survives whole; the new note keeps what fits.
  expect(person?.context).toHaveLength(4000);
  expect(person?.context?.startsWith("x".repeat(10))).toBe(true);
  expect(person?.context?.endsWith("y")).toBe(true);

  // No room at all: the save still lands, but says the note was cut, so a
  // drain never mistakes a clipped save for a complete one.
  const dropped = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    note: "lost words",
  });
  expect(dropped).toEqual({
    status: "already",
    personId: big.personId,
    noteTruncated: true,
    handleDropped: false,
  });
});

test("saveSharedProfile keeps the shared URL on a person that has none", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tr\u1ea7n",
  });
  const linkedin = {
    platform: "linkedin",
    handleValue: "mai-tran-8a91b2",
    profileUrl: "https://www.linkedin.com/in/mai-tran-8a91b2",
    name: "Mai Tran",
  };

  const attached = await as.mutation(api.people.saveSharedProfile, {
    ...linkedin,
    attachToPersonId: personId,
  });
  expect(attached).toEqual({ status: "attached", personId, noteTruncated: false, handleDropped: false });
  // Nothing can rebuild a LinkedIn URL from its slug, so dropping it here
  // makes the captured profile unopenable for good.
  expect((await as.query(api.people.getPerson, { id: personId }))?.link).toBe(
    "https://www.linkedin.com/in/mai-tran-8a91b2",
  );

  // A re-share never overwrites the link the person already has.
  const again = await as.mutation(api.people.saveSharedProfile, {
    ...linkedin,
    profileUrl: "https://linkedin.com/in/mai-tran-8a91b2?utm=share",
  });
  expect(again).toEqual({ status: "already", personId, noteTruncated: false, handleDropped: false });
  expect((await as.query(api.people.getPerson, { id: personId }))?.link).toBe(
    "https://www.linkedin.com/in/mai-tran-8a91b2",
  );
});

test("saveSharedProfile gives a re-shared person the URL they were saved without", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tr\u1ea7n",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });

  const result = await as.mutation(api.people.saveSharedProfile, sharedProfile);
  expect(result).toEqual({ status: "already", personId, noteTruncated: false, handleDropped: false });
  expect((await as.query(api.people.getPerson, { id: personId }))?.link).toBe(
    "https://instagram.com/mai.makes",
  );
});

test("saveSharedProfile stores a handle shared with a leading @ in its bare form", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const result = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    handleValue: "@binh.le",
    profileUrl: "https://instagram.com/binh.le",
    name: "Binh Le",
  });

  // The stored value and the identity key have to be the same shape, or the
  // card shows "@binh.le" or "binh.le" purely by which share landed first.
  const person = await as.query(api.people.getPerson, { id: result.personId });
  expect(displayOnly(person?.contactHandles)).toEqual([
    { platform: "instagram", value: "binh.le" },
  ]);
  const hits = await as.query(api.people.searchDirectory, {
    keyword: "binh.le",
  });
  expect(hits.map((p) => p._id)).toEqual([result.personId]);
});

test("saveSharedProfile keeps the handle index scoped to one user", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  const mine = await me.as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    note: "met at the ceramics market",
  });
  // The same account, shared by somebody else: two directories, two people.
  const theirs = await other.as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    note: "sat next to me on the flight",
  });
  expect(mine.status).toBe("created");
  expect(theirs.status).toBe("created");
  expect(theirs.personId).not.toBe(mine.personId);

  expect(
    await me.as.query(api.people.getPerson, { id: theirs.personId }),
  ).toBe(null);
  expect(
    (await me.as.query(api.people.getPerson, { id: mine.personId }))?.context,
  ).toBe("met at the ceramics market");
  expect(
    (await other.as.query(api.people.getPerson, { id: theirs.personId }))
      ?.context,
  ).toBe("sat next to me on the flight");
});

test("saveSharedProfile self-heals an orphaned handle row instead of shadowing the capture", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const first = await as.mutation(api.people.saveSharedProfile, sharedProfile);
  // A write that bypassed deletePerson leaves the index row behind.
  await t.run((ctx) => ctx.db.delete("people", first.personId));

  const again = await as.mutation(api.people.saveSharedProfile, sharedProfile);
  expect(again.status).toBe("created");
  expect(again.personId).not.toBe(first.personId);

  // The orphan is gone; the handle now indexes only the new person.
  const rows = await t.run((ctx) =>
    ctx.db.query("personHandles").collect(),
  );
  expect(rows.map((row) => row.personId)).toEqual([again.personId]);
});

test("saveSharedProfile heals a drifted searchText on a bare re-share", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const created = await as.mutation(
    api.people.saveSharedProfile,
    sharedProfile,
  );
  // A formula change since the row was written leaves searchText stale; the
  // re-share is the one moment the row is already in hand to heal it.
  await t.run((ctx) =>
    ctx.db.patch("people", created.personId, { searchText: "stale" }),
  );
  const before = await t.run((ctx) => ctx.db.get("people", created.personId));

  const again = await as.mutation(api.people.saveSharedProfile, sharedProfile);
  expect(again).toEqual({ status: "already", personId: created.personId, noteTruncated: false, handleDropped: false });
  const person = await t.run((ctx) => ctx.db.get("people", created.personId));
  expect(person?.searchText).toContain("mai.makes");
  // A heal is not an edit: recency stays put.
  expect(person?.updatedAt).toBe(before?.updatedAt);
});

test("saveSharedProfile rejects blank identity fields", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  // Blanks are programmer errors -- the extension only enqueues parsed
  // profiles -- so refusing is correct where clamping a note is not.
  await expect(
    as.mutation(api.people.saveSharedProfile, { ...sharedProfile, name: " " }),
  ).rejects.toThrow("Name is required");
  await expect(
    as.mutation(api.people.saveSharedProfile, {
      ...sharedProfile,
      platform: "  ",
    }),
  ).rejects.toThrow("A platform cannot be blank");
  // "@" alone is a handle only in punctuation.
  await expect(
    as.mutation(api.people.saveSharedProfile, {
      ...sharedProfile,
      handleValue: " @ ",
    }),
  ).rejects.toThrow("A handle cannot be blank");
});

test("saveSharedProfile rejects a phone value with no digit at all", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  await expect(
    as.mutation(api.people.saveSharedProfile, {
      ...sharedProfile,
      platform: "phone",
      handleValue: "unknown",
      profileUrl: "",
    }),
  ).rejects.toThrow("A phone number needs at least one digit");
});

test("saveSharedProfile rejects an unauthenticated caller", async () => {
  const t = convexTest(schema, modules);
  await expect(
    t.mutation(api.people.saveSharedProfile, sharedProfile),
  ).rejects.toThrow("Not signed in");
});

test("saveSharedProfile is rate-limited per caller (wiring check)", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  await as.mutation(api.people.saveSharedProfile, sharedProfile);

  const window = await t.run((ctx) =>
    ctx.db
      .query("rateLimits")
      .withIndex("by_user_action", (q) =>
        q.eq("userId", userId).eq("action", "saveSharedProfile"),
      )
      .unique(),
  );
  expect(window?.count).toBe(1);
});

// --------------------------------------------- handle index maintenance

test("addPerson makes its contact handles dedup-visible to saveSharedProfile", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tr\u1ea7n",
    contactHandles: [{ platform: " Instagram ", value: "@mai.makes" }],
  });

  const result = await as.mutation(api.people.saveSharedProfile, sharedProfile);
  expect(result).toEqual({ status: "already", personId, noteTruncated: false, handleDropped: false });
});

test("editPerson rewrites the handle index in both directions", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tr\u1ea7n",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });

  await as.mutation(api.people.editPerson, {
    id: personId,
    contactHandles: [{ platform: "linkedin", value: "mai-tran-8a91b2" }],
  });

  // The dropped handle belongs to nobody again...
  const freed = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    name: "Someone Else",
  });
  expect(freed.status).toBe("created");
  expect(freed.personId).not.toBe(personId);

  // ...and the added one dedups from the moment the edit lands.
  const dedup = await as.mutation(api.people.saveSharedProfile, {
    platform: "linkedin",
    handleValue: "mai-tran-8a91b2",
    profileUrl: "https://linkedin.com/in/mai-tran-8a91b2",
    name: "Mai Tran",
  });
  expect(dedup).toEqual({ status: "already", personId, noteTruncated: false, handleDropped: false });
});

test("deletePerson frees the handle for a later share", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tr\u1ea7n",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });

  await as.mutation(api.people.deletePerson, { personId });
  expect(
    await t.run((ctx) => ctx.db.query("personHandles").collect()),
  ).toHaveLength(0);

  // A ghost row here would resurrect a deleted person in every lookup.
  const result = await as.mutation(api.people.saveSharedProfile, sharedProfile);
  expect(result.status).toBe("created");
});

// Drive the paged backfill the way an operator does: run it, feed the cursor
// back, stop when it says it is done. Bounded so a broken cursor fails the
// test instead of hanging it.
async function drainPersonHandlesBackfill(
  t: ReturnType<typeof convexTest>,
): Promise<{ patched: number; refused: number }> {
  let cursor: string | null = null;
  let patched = 0;
  let refused = 0;
  for (let page = 0; page < 20; page++) {
    // Annotated because the cursor fed back in would otherwise make the
    // inferred result type circular.
    const result: {
      patched: number;
      refused: number;
      isDone: boolean;
      cursor: string;
    } = await t.mutation(internal.people.backfillPersonHandles, { cursor });
    patched += result.patched;
    refused += result.refused;
    if (result.isDone) {
      return { patched, refused };
    }
    cursor = result.cursor;
  }
  throw new Error("backfillPersonHandles never finished");
}

test("backfillPersonHandles indexes handles written before the index existed", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const legacyId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai Tr\u1ea7n",
      normalizedName: "mai tran",
      contactHandles: [{ platform: "instagram", value: "mai.makes" }],
      updatedAt: Date.now(),
    }),
  );
  // A person with no handles is nothing to backfill.
  await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Binh Le",
      normalizedName: "binh le",
      updatedAt: Date.now(),
    }),
  );

  expect(await drainPersonHandlesBackfill(t)).toEqual({ patched: 1, refused: 0 });
  const shared = await as.mutation(api.people.saveSharedProfile, sharedProfile);
  expect(shared).toEqual({ status: "already", personId: legacyId, noteTruncated: false, handleDropped: false });

  // Idempotent: a second run has nothing left to index.
  expect(await drainPersonHandlesBackfill(t)).toEqual({ patched: 0, refused: 0 });
  expect(
    await t.run((ctx) => ctx.db.query("personHandles").collect()),
  ).toHaveLength(1);
});

test("backfillPersonHandles pages past the first batch", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  // One more than BACKFILL_BATCH_SIZE: a single un-cursored scan would report
  // "done" while the tail stays unindexed, and unindexed people get twinned
  // the first time their handle is shared.
  const total = 501;
  await t.run(async (ctx) => {
    for (let i = 0; i < total; i++) {
      await ctx.db.insert("people", {
        userId,
        name: `Person ${i}`,
        normalizedName: `person ${i}`,
        contactHandles: [{ platform: "instagram", value: `handle${i}` }],
        updatedAt: Date.now(),
      });
    }
  });

  expect(await drainPersonHandlesBackfill(t)).toEqual({ patched: total, refused: 0 });
  expect(
    await t.run((ctx) => ctx.db.query("personHandles").collect()),
  ).toHaveLength(total);
});

// W1: backfillLegacyHandles (below) gates a digitless phone/whatsapp value
// before folding it into the index -- this sibling migration, which indexes
// contactHandles entries that ALREADY exist but have no personHandles row
// yet, sent them straight to insertPersonHandles with no such gate. Two
// legacy people who each stored an unreadable phone value under a different
// case ("unknown" / "Unknown", the same fold once lowercased) would both
// index under one valueKey the moment this ran.
test("backfillPersonHandles skips a digitless phone value and counts it refused, so two legacy people never share a valueKey", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  const alice = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Alice",
      normalizedName: "alice",
      contactHandles: [{ platform: "phone", value: "unknown" }],
      updatedAt: Date.now(),
    }),
  );
  const bob = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Bob",
      normalizedName: "bob",
      contactHandles: [{ platform: "phone", value: "Unknown" }],
      updatedAt: Date.now(),
    }),
  );

  expect(await drainPersonHandlesBackfill(t)).toEqual({ patched: 0, refused: 2 });

  // Neither row was indexed -- there is nothing for a later share of
  // "unknown" to attach to, and Alice and Bob never share a valueKey.
  expect(await t.run((ctx) => ctx.db.query("personHandles").collect())).toEqual(
    [],
  );
  expect(alice).not.toBe(bob);
});

// ------------------------------------------ legacy scalar identity backfill

// Drive the paged migration the way an operator does: run it, feed the
// cursor back, stop when it says it is done. Bounded so a broken cursor
// fails the test instead of hanging it.
async function drainLegacyHandlesBackfill(
  t: ReturnType<typeof convexTest>,
): Promise<{ patched: number; skipped: number; refused: number }> {
  let cursor: string | null = null;
  let patched = 0;
  let skipped = 0;
  let refused = 0;
  for (let page = 0; page < 20; page++) {
    // Annotated because the cursor fed back in would otherwise make the
    // inferred result type circular.
    const result: {
      patched: number;
      skipped: number;
      refused: number;
      isDone: boolean;
      cursor: string;
    } = await t.mutation(internal.people.backfillLegacyHandles, { cursor });
    patched += result.patched;
    skipped += result.skipped;
    refused += result.refused;
    if (result.isDone) {
      return { patched, skipped, refused };
    }
    cursor = result.cursor;
  }
  throw new Error("backfillLegacyHandles never finished");
}

test("backfillLegacyHandles folds legacy scalars into the identity index", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const updatedAt = Date.now() - 60_000;
  // A person written by the screenshot pipeline before it maintained the
  // index: reachable on Instagram, invisible to every handle lookup.
  const legacyId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai Tr\u1ea7n",
      normalizedName: "mai tran",
      platform: "Instagram",
      handle: "@Mai.Makes",
      updatedAt,
    }),
  );

  expect(await drainLegacyHandlesBackfill(t)).toEqual({
    patched: 1,
    skipped: 0,
    refused: 0,
  });

  const person = await t.run((ctx) => ctx.db.get("people", legacyId));
  expect(person?.contactHandles).toEqual([
    { platform: "instagram", value: "Mai.Makes" },
  ]);
  // A migration is not an edit: it must not reshuffle the directory's
  // recency order under the user.
  expect(person?.updatedAt).toBe(updatedAt);
  expect(
    await t.run((ctx) => ctx.db.query("personHandles").take(10)),
  ).toMatchObject([
    { userId, personId: legacyId, platform: "instagram", valueKey: "mai.makes" },
  ]);

  // The point of the whole migration: a later share finds them instead of
  // twinning them.
  expect(await as.mutation(api.people.saveSharedProfile, sharedProfile)).toEqual(
    { status: "already", personId: legacyId, noteTruncated: false, handleDropped: false },
  );

  // Idempotent: a second pass to done has nothing left to patch, and the
  // person it already covered is now counted as skipped.
  expect(await drainLegacyHandlesBackfill(t)).toEqual({
    patched: 0,
    skipped: 1,
    refused: 0,
  });
  expect(
    await t.run((ctx) => ctx.db.query("personHandles").take(10)),
  ).toHaveLength(1);
});

test("backfillLegacyHandles appends beside handles on other platforms", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  const personId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai Tr\u1ea7n",
      normalizedName: "mai tran",
      contactHandles: [{ platform: "linkedin", value: "mai-tran-8a91b2" }],
      platform: "instagram",
      handle: "mai.makes",
      updatedAt: Date.now(),
    }),
  );

  expect(await drainLegacyHandlesBackfill(t)).toEqual({
    patched: 1,
    skipped: 0,
    refused: 0,
  });

  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person?.contactHandles).toEqual([
    { platform: "linkedin", value: "mai-tran-8a91b2" },
    { platform: "instagram", value: "mai.makes" },
  ]);
});

test("backfillLegacyHandles never overwrites a platform the array already holds", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  // The array and the legacy scalars disagree about which Instagram account
  // this is. Picking a winner is a product decision, not a migration's.
  const personId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai Tr\u1ea7n",
      normalizedName: "mai tran",
      contactHandles: [{ platform: "instagram", value: "mai.makes" }],
      platform: "Instagram",
      handle: "@an.old.account",
      updatedAt: Date.now(),
    }),
  );

  expect(await drainLegacyHandlesBackfill(t)).toEqual({
    patched: 0,
    skipped: 1,
    refused: 0,
  });
  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person?.contactHandles).toEqual([
    { platform: "instagram", value: "mai.makes" },
  ]);
  expect(await t.run((ctx) => ctx.db.query("personHandles").take(10))).toEqual(
    [],
  );
});

// X2b: a digitless phone/whatsapp scalar folds through handleValueKey's own
// lowercase fallback, the same collision risk validateContactHandles gates
// on every live write path (identity brief, R1) -- this maintenance path
// has to refuse it too, or a legacy row written before that gate existed
// could still be folded into the index and collide with a stranger's.
test("backfillLegacyHandles skips a digitless phone scalar and counts it refused", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  const personId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Alice",
      normalizedName: "alice",
      platform: "phone",
      handle: "unknown",
      updatedAt: Date.now(),
    }),
  );

  expect(await drainLegacyHandlesBackfill(t)).toEqual({
    patched: 0,
    skipped: 0,
    refused: 1,
  });
  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person?.contactHandles).toBeUndefined();
  expect(await t.run((ctx) => ctx.db.query("personHandles").take(10))).toEqual(
    [],
  );
});

// The reviewer's exact chain (X2, R1's two-person scenario replayed through
// the maintenance path instead of a live capture): a legacy Alice and a
// legacy Bob each carry a digitless phone scalar under a different case
// ("unknown" / "Unknown", the same fold once lowercased) -- exactly what a
// pre-fix acceptCapture would have written before this brief's R1 gate
// existed. Running the backfill over both must not fold either into the
// index: no shared valueKey ever appears, so no later write can attach one
// to the other by reading personHandles.
test("backfillLegacyHandles never creates a shared valueKey between two legacy digitless phone rows", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  const alice = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Alice",
      normalizedName: "alice",
      platform: "phone",
      handle: "unknown",
      updatedAt: Date.now(),
    }),
  );
  const bob = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Bob",
      normalizedName: "bob",
      platform: "phone",
      handle: "Unknown",
      updatedAt: Date.now(),
    }),
  );

  expect(await drainLegacyHandlesBackfill(t)).toEqual({
    patched: 0,
    skipped: 0,
    refused: 2,
  });

  // Neither row gained a contactHandles entry or a personHandles row --
  // there is nothing for a later share of "unknown" to attach to.
  const aliceAfter = await t.run((ctx) => ctx.db.get("people", alice));
  const bobAfter = await t.run((ctx) => ctx.db.get("people", bob));
  expect(aliceAfter?.contactHandles).toBeUndefined();
  expect(bobAfter?.contactHandles).toBeUndefined();
  expect(await t.run((ctx) => ctx.db.query("personHandles").take(10))).toEqual(
    [],
  );
});

test("backfillLegacyHandles leaves people with nothing to fold alone", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  await t.run(async (ctx) => {
    // Name-only, the honest state of a capture with no visible handle.
    await ctx.db.insert("people", {
      userId,
      name: "Binh Le",
      normalizedName: "binh le",
      updatedAt: Date.now(),
    });
    // A platform with no handle names no account, and a handle with no
    // platform cannot be indexed: neither is a person to touch.
    await ctx.db.insert("people", {
      userId,
      name: "Vy Ho",
      normalizedName: "vy ho",
      platform: "instagram",
      updatedAt: Date.now(),
    });
    await ctx.db.insert("people", {
      userId,
      name: "Nam Pham",
      normalizedName: "nam pham",
      handle: "@nam",
      updatedAt: Date.now(),
    });
    // A handle of punctuation alone folds to nothing at all.
    await ctx.db.insert("people", {
      userId,
      name: "Linh Do",
      normalizedName: "linh do",
      platform: "instagram",
      handle: " @ ",
      updatedAt: Date.now(),
    });
  });

  expect(await drainLegacyHandlesBackfill(t)).toEqual({
    patched: 0,
    skipped: 0,
    refused: 0,
  });
  expect(await t.run((ctx) => ctx.db.query("personHandles").take(10))).toEqual(
    [],
  );
});

test("backfillLegacyHandles pages past the first batch", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  // One more than BACKFILL_BATCH_SIZE: a single un-cursored scan would report
  // "done" while the tail keeps its unindexed identity, which is exactly the
  // corruption this migration exists to end.
  const total = 501;
  await t.run(async (ctx) => {
    for (let i = 0; i < total; i++) {
      await ctx.db.insert("people", {
        userId,
        name: `Person ${i}`,
        normalizedName: `person ${i}`,
        platform: "instagram",
        handle: `handle${i}`,
        updatedAt: Date.now(),
      });
    }
  });

  expect(await drainLegacyHandlesBackfill(t)).toEqual({
    patched: total,
    skipped: 0,
    refused: 0,
  });
  expect(
    await t.run((ctx) => ctx.db.query("personHandles").take(total + 1)),
  ).toHaveLength(total);
});

// ------------------------------------------------ phone handle key backfill

// Drive the paged migration the way an operator does: run it, feed the
// cursor back, stop when it says it is done. Bounded so a broken cursor
// fails the test instead of hanging it.
async function drainPhoneHandleKeysBackfill(
  t: ReturnType<typeof convexTest>,
): Promise<number> {
  let cursor: string | null = null;
  let patched = 0;
  for (let page = 0; page < 20; page++) {
    // Annotated because the cursor fed back in would otherwise make the
    // inferred result type circular.
    const result: { patched: number; isDone: boolean; cursor: string } =
      await t.mutation(internal.people.backfillPhoneHandleKeys, { cursor });
    patched += result.patched;
    if (result.isDone) {
      return patched;
    }
    cursor = result.cursor;
  }
  throw new Error("backfillPhoneHandleKeys never finished");
}

test("backfillPhoneHandleKeys recomputes a stale key from the old trim+lowercase fold", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  const personId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai Tr\u1ea7n",
      normalizedName: "mai tran",
      contactHandles: [{ platform: "phone", value: "+1 415 555 0123" }],
      updatedAt: Date.now(),
    }),
  );
  // What the old fold (trim + lowercase) actually wrote: the spaces survive,
  // since there is nothing to lowercase in a number. The new fold reads the
  // same source string as one E.164 value.
  await t.run((ctx) =>
    ctx.db.insert("personHandles", {
      userId,
      personId,
      platform: "phone",
      valueKey: "+1 415 555 0123",
    }),
  );

  expect(await drainPhoneHandleKeysBackfill(t)).toBe(1);
  const rows = await t.run((ctx) =>
    ctx.db
      .query("personHandles")
      .withIndex("by_person", (q) => q.eq("personId", personId))
      .collect(),
  );
  expect(rows).toHaveLength(1);
  expect(rows[0].valueKey).toBe("+14155550123");

  // Idempotent: a second run has nothing left to patch.
  expect(await drainPhoneHandleKeysBackfill(t)).toBe(0);
});

test("backfillPhoneHandleKeys leaves non-phone platforms and already-current keys alone", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  const personId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Binh Le",
      normalizedName: "binh le",
      contactHandles: [
        { platform: "instagram", value: "binh.le" },
        { platform: "phone", value: "+14155550123" },
      ],
      updatedAt: Date.now(),
    }),
  );
  await t.run(async (ctx) => {
    await ctx.db.insert("personHandles", {
      userId,
      personId,
      platform: "instagram",
      valueKey: "binh.le",
    });
    await ctx.db.insert("personHandles", {
      userId,
      personId,
      platform: "phone",
      valueKey: "+14155550123",
    });
  });

  expect(await drainPhoneHandleKeysBackfill(t)).toBe(0);
});

// ------------------------------------------- duplicate handle owner report

// Drain the report the way an operator does, page by page, so a group that
// straddles a page boundary has to survive the round trip.
async function collectDuplicateHandleOwners(
  t: ReturnType<typeof convexTest>,
  pageSize?: number,
): Promise<
  Array<{
    userId: string;
    platform: string;
    valueKey: string;
    personIds: string[];
  }>
> {
  let cursor: string | null = null;
  const duplicates = [];
  for (let page = 0; page < 20; page++) {
    // Annotated because the cursor fed back in would otherwise make the
    // inferred result type circular.
    const result: {
      duplicates: Array<{
        userId: string;
        platform: string;
        valueKey: string;
        personIds: string[];
      }>;
      scanned: number;
      isDone: boolean;
      cursor: string;
    } = await t.query(internal.people.reportDuplicateHandleOwners, {
      cursor,
      pageSize,
    });
    duplicates.push(...result.duplicates);
    if (result.isDone) {
      return duplicates;
    }
    cursor = result.cursor;
  }
  throw new Error("reportDuplicateHandleOwners never finished");
}

test("reportDuplicateHandleOwners finds the twins one account spawned", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const other = asNewUser(t);
  // addPerson and editPerson now gate new writes against this exact
  // corruption (identity brief, task 2), so the twins are seeded directly
  // rather than through addPerson, which would refuse to create the second
  // one -- see "addPerson twice with the same handle" for that guarantee.
  // A duplicate can still reach the table from before that gate, or from a
  // path this file does not cover, which is what this report exists to find.
  const first = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai Tran",
      normalizedName: "mai tran",
      contactHandles: [{ platform: "instagram", value: "mai.makes" }],
      updatedAt: Date.now(),
    }),
  );
  const second = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai T.",
      normalizedName: "mai t.",
      contactHandles: [{ platform: "instagram", value: "@Mai.Makes" }],
      updatedAt: Date.now(),
    }),
  );
  await t.run(async (ctx) => {
    await ctx.db.insert("personHandles", {
      userId,
      personId: first,
      platform: "instagram",
      valueKey: "mai.makes",
    });
    await ctx.db.insert("personHandles", {
      userId,
      personId: second,
      platform: "instagram",
      valueKey: "mai.makes",
    });
  });
  // A handle only one person owns is not a duplicate...
  await as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "Binh Le",
    contactHandles: [{ platform: "linkedin", value: "binh-le" }],
  });
  // ...and the same account in someone else's directory is their own person,
  // never a duplicate of mine.
  await other.as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "Mai Tran",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });

  expect(await collectDuplicateHandleOwners(t)).toEqual([
    {
      userId,
      platform: "instagram",
      valueKey: "mai.makes",
      personIds: [first, second],
    },
  ]);
});

test("reportDuplicateHandleOwners does not mistake a doubled row for a twin", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Mai Tran",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });
  // saveSharedProfile's attach path inserts an index row even when the array
  // already held that handle, so one person can own two identical rows. One
  // person owning their own account twice is not a duplicate owner.
  await t.run((ctx) =>
    ctx.db.insert("personHandles", {
      userId,
      personId,
      platform: "instagram",
      valueKey: "mai.makes",
    }),
  );

  expect(await collectDuplicateHandleOwners(t)).toEqual([]);
});

test("reportDuplicateHandleOwners reports a group split across pages once", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  // Raw rows keep the index order deterministic: with a page of one, the two
  // owners of the same account land in different pages. A grouping that only
  // looks within a page would miss them, and a naive fix would report them
  // twice -- either way the wave C decision is made on wrong numbers.
  const owners = await t.run(async (ctx) => {
    const a = await ctx.db.insert("people", {
      userId,
      name: "Mai Tran",
      updatedAt: Date.now(),
    });
    const b = await ctx.db.insert("people", {
      userId,
      name: "Mai T.",
      updatedAt: Date.now(),
    });
    for (const personId of [a, b]) {
      await ctx.db.insert("personHandles", {
        userId,
        personId,
        platform: "instagram",
        valueKey: "mai.makes",
      });
    }
    // A later key, so the split group is not simply the tail of the scan.
    await ctx.db.insert("personHandles", {
      userId,
      personId: a,
      platform: "linkedin",
      valueKey: "mai-tran",
    });
    return [a, b];
  });

  expect(await collectDuplicateHandleOwners(t, 1)).toEqual([
    {
      userId,
      platform: "instagram",
      valueKey: "mai.makes",
      personIds: owners,
    },
  ]);
});

// Same reasoning as the card: these are drawn on a row sized for a line, the
// client caps nothing today, and the server accepted a megabyte.
test("addPerson refuses fields longer than the row can draw", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);

  await expect(
    me.as.mutation(api.people.addPersonWithOutcome, {
      ...manualAdd,
      name: "N".repeat(41),
    }),
  ).rejects.toThrow("Keep a name under 40 characters");
  await expect(
    me.as.mutation(api.people.addPersonWithOutcome, {
      ...manualAdd,
      name: "Ada",
      company: "C".repeat(61),
    }),
  ).rejects.toThrow("under 60 characters");
  await expect(
    me.as.mutation(api.people.addPersonWithOutcome, {
      ...manualAdd,
      name: "Ada",
      role: "R".repeat(61),
    }),
  ).rejects.toThrow("under 60 characters");
  await expect(
    me.as.mutation(api.people.addPersonWithOutcome, {
      ...manualAdd,
      name: "Ada",
      city: { name: "C".repeat(41) },
    }),
  ).rejects.toThrow("under 40 characters");
  await expect(
    me.as.mutation(api.people.addPersonWithOutcome, {
      name: "Ada",
      context: "met at the compiler meetup",
      contactHandles: [{ platform: "phone", value: "1".repeat(61) }],
    }),
  ).rejects.toThrow("under 60 characters");

  // Nothing landed on the way through any of those.
  expect(await t.run((ctx) => ctx.db.query("people").collect())).toEqual([]);
});

test("editPerson refuses the same fields the same way", async () => {
  const t = convexTest(schema, modules);
  const me = asNewUser(t);
  const id = await addPersonId(me.as, {
    ...manualAdd,
    name: "Ada Lovelace",
  });

  await expect(
    me.as.mutation(api.people.editPerson, { id, name: "N".repeat(41) }),
  ).rejects.toThrow("under 40 characters");
  await expect(
    me.as.mutation(api.people.editPerson, { id, company: "C".repeat(61) }),
  ).rejects.toThrow("under 60 characters");

  const person = await me.as.query(api.people.getPerson, { id });
  expect(person?.name).toBe("Ada Lovelace");
});

// The capture lookup used .first(), which silently picked one owner when a
// handle had two -- arbitrary, and it hid the corruption. addPerson and
// editPerson now gate new writes so this cannot happen going forward, but a
// row from before that gate (or from a path this file does not cover) can
// still leave two, and a capture queue draining unattended must not jam on
// it. The rows are seeded directly rather than through addPerson, which now
// refuses to create the second one -- see "addPerson twice with the same
// handle" above for that guarantee.
test("a shared profile attaches to the oldest of two owners instead of throwing", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const older = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai Tran",
      normalizedName: "mai tran",
      contactHandles: [{ platform: "instagram", value: "mai.makes" }],
      updatedAt: Date.now(),
    }),
  );
  const younger = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai T.",
      normalizedName: "mai t.",
      contactHandles: [{ platform: "instagram", value: "@Mai.Makes" }],
      updatedAt: Date.now(),
    }),
  );
  await t.run(async (ctx) => {
    await ctx.db.insert("personHandles", {
      userId,
      personId: older,
      platform: "instagram",
      valueKey: "mai.makes",
    });
    await ctx.db.insert("personHandles", {
      userId,
      personId: younger,
      platform: "instagram",
      valueKey: "mai.makes",
    });
  });

  const result = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "mai.makes",
    profileUrl: "https://instagram.com/mai.makes",
    name: "Mai Tran",
    note: "ran into her again",
  });
  expect(result.status).toBe("already");
  expect(result.personId).toBe(older);

  const person = await t.run((ctx) => ctx.db.get("people", older));
  expect(person?.context).toContain("ran into her again");
});

test("findHandleOwner tiebreaks on the owner PERSON's age, not a reindexed row's", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const older = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai Tran",
      normalizedName: "mai tran",
      contactHandles: [{ platform: "instagram", value: "mai.makes" }],
      updatedAt: Date.now(),
    }),
  );
  const younger = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Mai T.",
      normalizedName: "mai t.",
      contactHandles: [{ platform: "instagram", value: "@Mai.Makes" }],
      updatedAt: Date.now(),
    }),
  );
  // younger's index row is written FIRST here, older's SECOND -- standing in
  // for older's row being rewritten later (a rename, deletePersonHandles +
  // insertPersonHandles from an unrelated edit) long after both PEOPLE were
  // created. personHandles._creationTime resets on every reindex, so a
  // tiebreak on the row's own age would pick younger; the owner person's age
  // has to win instead.
  await t.run(async (ctx) => {
    await ctx.db.insert("personHandles", {
      userId,
      personId: younger,
      platform: "instagram",
      valueKey: "mai.makes",
    });
    await ctx.db.insert("personHandles", {
      userId,
      personId: older,
      platform: "instagram",
      valueKey: "mai.makes",
    });
  });

  const result = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "mai.makes",
    profileUrl: "https://instagram.com/mai.makes",
    name: "Mai Tran",
    note: "ran into her again",
  });
  expect(result.personId).toBe(older);
});

// The index query is already scoped to the caller's own userId, so the only
// way a cross-tenant row reaches oldestLiveOwner is a row whose OWN userId
// matches (so the index finds it) but whose personId points at a person now
// owned by somebody else -- a stale/corrupt pointer, not a stale index. The
// belt checks the loaded owner's own userId, not just the row's.
test("findHandleOwner refuses to return a person owned by a different tenant", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const stranger = await asNewUser(t);
  const strangersPerson = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId: stranger.userId,
      name: "Rao",
      normalizedName: "rao",
      contactHandles: [{ platform: "instagram", value: "mai.makes" }],
      updatedAt: Date.now(),
    }),
  );
  // A row that claims the CALLER's userId (so the index finds it) but whose
  // personId points at a person belonging to somebody else -- exactly the
  // corrupt-pointer shape the belt exists to catch, however it got written.
  await t.run((ctx) =>
    ctx.db.insert("personHandles", {
      userId,
      personId: strangersPerson,
      platform: "instagram",
      valueKey: "mai.makes",
    }),
  );

  const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
  const result = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "mai.makes",
    profileUrl: "https://instagram.com/mai.makes",
    name: "Mai Tran",
    note: "met at the market",
  });
  errorSpy.mockRestore();

  // No owner found through the corrupt row: this creates fresh rather than
  // attaching to a person that belongs to a different tenant entirely.
  expect(result.status).toBe("created");
  expect(result.personId).not.toBe(strangersPerson);
});
