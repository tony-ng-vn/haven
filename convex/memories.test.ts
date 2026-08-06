/// <reference types="vite/client" />
import { convexTest, type TestConvexForDataModel } from "convex-test";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import type {
  DataModelFromSchemaDefinition,
  FunctionArgs,
} from "convex/server";
import { api, internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import schema from "./schema";
import { MAX_MEMORIES_PER_PERSON } from "./memories";

const modules = import.meta.glob("./**/*.ts");

// Inferred from the call rather than written out: the helpers below read the
// memories table by index, which only typechecks against a data model that
// knows the table exists -- and a bare ReturnType<typeof convexTest> does not.
function newHarness() {
  return convexTest(schema, modules);
}
type Harness = ReturnType<typeof newHarness>;
type TestDataModel = DataModelFromSchemaDefinition<typeof schema>;

// addPerson now returns a creation outcome, not a bare id (identity brief,
// task 2). Every call in this file exists only to seed a person memories
// tests then act on, so this unwraps the common case and throws loudly if a
// seed unexpectedly collides with an existing handle instead of creating.
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

// Mint a fake Clerk identity and return an authenticated test context bound
// to it. requireUser() keys ownership on tokenIdentifier ("issuer|subject"),
// which is what convex-test's withIdentity() synthesizes here.
let nextSubject = 0;
function asNewUser(t: Harness) {
  const subject = `memory_user_${nextSubject++}`;
  const issuer = "https://test.clerk.accounts.dev";
  const userId = `${issuer}|${subject}`;
  return { userId, as: t.withIdentity({ subject, issuer }) };
}

// A deterministic 1536-dim unit vector with a 1 at the given position, so
// cosine similarity against another unit vector is exactly 1 or 0.
function unitVector(hotIndex: number): number[] {
  const vector = new Array(1536).fill(0);
  vector[hotIndex] = 1;
  return vector;
}

// Stub only the embeddings endpoint; anything else falls through to the real
// fetch. Attempts are counted per input text, because saving a person embeds
// the person and each line of their note independently -- a global counter
// could not tell one target's retries from another's.
function stubEmbeddings(
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
      if (
        url.hostname === "api.openai.com" &&
        url.pathname.includes("/embeddings")
      ) {
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

function stubEmbedding(vector: number[]) {
  return stubEmbeddings(() => Response.json({ data: [{ embedding: vector }] }));
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

// addPerson requires a handle and a note; tests that are not about that rule
// spread this minimal valid payload and override what they exercise.
const manualAdd = {
  contactHandles: [{ platform: "phone", value: "unlisted1" }],
  context: "met at the compiler meetup",
};

async function memoriesOf(t: Harness, personId: Id<"people">) {
  return await t.run((ctx) =>
    ctx.db
      .query("memories")
      .withIndex("by_person", (q) => q.eq("personId", personId))
      .collect(),
  );
}

// ------------------------------------------------------------ write paths

test("addPerson records its note as a memory owned by the caller", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);

  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Ada Lovelace",
  });

  const memories = await memoriesOf(t, personId);
  expect(memories.map((m) => m.text)).toEqual(["met at the compiler meetup"]);
  expect(memories[0].userId).toBe(userId);
  expect(typeof memories[0].createdAt).toBe("number");
});

test("a multi-line note becomes one memory per line", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);

  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Ada Lovelace",
    context: "met at the meetup\n\nworks on an infinite-context database\n  ",
  });

  expect((await memoriesOf(t, personId)).map((m) => m.text)).toEqual([
    "met at the meetup",
    "works on an infinite-context database",
  ]);
});

test("editPerson adds only the new line and re-running it adds nothing", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Ada Lovelace",
  });

  const next = `${manualAdd.context}\nintroduced by Grace`;
  await as.mutation(api.people.editPerson, { id: personId, context: next });
  await as.mutation(api.people.editPerson, { id: personId, context: next });

  expect((await memoriesOf(t, personId)).map((m) => m.text)).toEqual([
    manualAdd.context,
    "introduced by Grace",
  ]);
});

test("clearing the context keeps the memories already recorded", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Ada Lovelace",
  });

  await as.mutation(api.people.editPerson, { id: personId, context: null });

  expect((await memoriesOf(t, personId)).map((m) => m.text)).toEqual([
    manualAdd.context,
  ]);
});

test("updatePerson records the note it writes", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Ada Lovelace",
  });

  await as.mutation(api.people.updatePerson, {
    id: personId,
    context: "runs the Founder Inc dinners",
  });

  expect((await memoriesOf(t, personId)).map((m) => m.text)).toContain(
    "runs the Founder Inc dinners",
  );
});

test("saveSharedProfile records the note on create, re-share, and attach", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);

  const created = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "@ada",
    profileUrl: "https://instagram.com/ada",
    name: "Ada Lovelace",
    note: "met at the meetup",
  });
  const reshared = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "ada",
    profileUrl: "https://instagram.com/ada",
    name: "Ada Lovelace",
    note: "works on compilers",
  });
  expect(reshared.status).toBe("already");
  expect((await memoriesOf(t, created.personId)).map((m) => m.text)).toEqual([
    "met at the meetup",
    "works on compilers",
  ]);

  const attached = await as.mutation(api.people.saveSharedProfile, {
    platform: "x",
    handleValue: "@ada_l",
    profileUrl: "https://x.com/ada_l",
    name: "Ada Lovelace",
    note: "also on X",
    attachToPersonId: created.personId,
  });
  expect(attached.status).toBe("attached");
  expect((await memoriesOf(t, created.personId)).map((m) => m.text)).toContain(
    "also on X",
  );
});

test("acceptCapture records its note as a memory", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  const screenshotId = await t.run((ctx) =>
    ctx.storage.store(new Blob(["fake"], { type: "image/png" })),
  );
  const captureId = await t.run((ctx) =>
    ctx.db.insert("captures", {
      userId,
      screenshotId,
      status: "ready",
      extracted: { platform: "x", name: "Ada Lovelace", handle: "@ada_l" },
    }),
  );

  const acceptedCapture = await as.mutation(api.captures.acceptCapture, {
    captureId,
    context: "screenshotted from the timeline",
  });
  if (acceptedCapture.status !== "created") throw new Error("unreachable");
  const personId = acceptedCapture.personId;

  expect((await memoriesOf(t, personId)).map((m) => m.text)).toEqual([
    "screenshotted from the timeline",
  ]);
});

test("acceptManualCapture records its note as a memory", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  const screenshotId = await t.run((ctx) =>
    ctx.storage.store(new Blob(["fake"], { type: "image/png" })),
  );
  const captureId = await t.run((ctx) =>
    ctx.db.insert("captures", {
      userId,
      screenshotId,
      status: "failed",
    }),
  );

  const acceptedManual = await as.mutation(api.captures.acceptManualCapture, {
    captureId,
    name: "Ada Lovelace",
    context: "the human read the screenshot",
  });
  if (acceptedManual.status !== "created") throw new Error("unreachable");
  const personId = acceptedManual.personId;

  expect((await memoriesOf(t, personId)).map((m) => m.text)).toEqual([
    "the human read the screenshot",
  ]);
});

test("deletePerson takes its memories with it", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Ada Lovelace",
  });
  expect(await memoriesOf(t, personId)).toHaveLength(1);

  await as.mutation(api.people.deletePerson, { personId });

  expect(await memoriesOf(t, personId)).toHaveLength(0);
});

test("a person's memories stop at the cap instead of growing forever", async () => {
  const t = newHarness();
  const { userId, as } = await asNewUser(t);
  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Ada Lovelace",
  });
  // One under the cap, so the next sync has room for exactly one line.
  await t.run(async (ctx) => {
    for (let i = 1; i < MAX_MEMORIES_PER_PERSON - 1; i++) {
      await ctx.db.insert("memories", {
        userId,
        personId,
        text: `filler ${i}`,
        createdAt: 1,
      });
    }
  });

  await as.mutation(api.people.editPerson, {
    id: personId,
    context: "first new line\nsecond new line",
  });

  const texts = (await memoriesOf(t, personId)).map((m) => m.text);
  expect(texts).toHaveLength(MAX_MEMORIES_PER_PERSON);
  expect(texts).toContain("first new line");
  expect(texts).not.toContain("second new line");
});

// ------------------------------------------------------------- embeddings

test("a new memory is embedded and re-embedding it is a no-op", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const stub = stubEmbedding(unitVector(3));

  const personId = await addPersonId(as, {
    ...manualAdd,
    name: "Ada Lovelace",
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const [memory] = await memoriesOf(t, personId);
  expect(memory.embedding).toEqual(unitVector(3));
  expect(memory.embeddedText).toBe(manualAdd.context);

  await t.action(internal.memories.embed, { memoryId: memory._id });
  expect(stub.attemptsFor(manualAdd.context)).toBe(1);
});

test("a failed memory embedding retries with backoff and then gives up", async () => {
  const t = newHarness();
  const { as } = await asNewUser(t);
  const stub = stubEmbeddings(() =>
    new Response("upstream error", { status: 500 }),
  );

  await as.mutation(api.people.addPersonWithOutcome, {
    ...manualAdd,
    name: "Ada Lovelace",
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  // One attempt plus the two scheduled retries in EMBED_RETRY_DELAYS_MS,
  // then it gives up rather than throwing out of the scheduler.
  expect(stub.attemptsFor(manualAdd.context)).toBe(3);
});

test("backfillMemoryEmbeddings fills in a memory whose embed never landed", async () => {
  const t = newHarness();
  const { userId } = await asNewUser(t);
  const personId = await t.run((ctx) =>
    ctx.db.insert("people", { userId, name: "Ada", updatedAt: 1 }),
  );
  await t.run((ctx) =>
    ctx.db.insert("memories", {
      userId,
      personId,
      text: "never embedded",
      createdAt: 1,
    }),
  );
  stubEmbedding(unitVector(4));

  const embedded = await t.action(internal.memories.backfillMemoryEmbeddings, {});

  expect(embedded).toBe(1);
  expect((await memoriesOf(t, personId))[0].embedding).toEqual(unitVector(4));
});

// --------------------------------------------------------------- migration

test("backfillMemories splits stored context and skips people it already did", async () => {
  const t = newHarness();
  const { userId } = await asNewUser(t);
  const personId = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Ada Lovelace",
      context: "met at the meetup\nworks on compilers",
      updatedAt: 4242,
    }),
  );

  const first = await t.mutation(internal.memories.backfillMemories, {});
  expect(first.isDone).toBe(true);
  expect(first.patched).toBe(1);
  expect(first.skipped).toBe(0);

  const memories = await memoriesOf(t, personId);
  expect(memories.map((m) => m.text)).toEqual([
    "met at the meetup",
    "works on compilers",
  ]);
  // Stamped with the person's own updatedAt, not the migration's clock: a
  // migration is not a new memory.
  expect(memories.every((m) => m.createdAt === 4242)).toBe(true);

  const second = await t.mutation(internal.memories.backfillMemories, {});
  expect(second.patched).toBe(0);
  expect(second.skipped).toBe(1);
  expect(await memoriesOf(t, personId)).toHaveLength(2);
});

test("backfillMemories ignores a person with no context", async () => {
  const t = newHarness();
  const { userId } = await asNewUser(t);
  await t.run((ctx) =>
    ctx.db.insert("people", { userId, name: "Ada", updatedAt: 1 }),
  );

  const result = await t.mutation(internal.memories.backfillMemories, {});

  expect(result.patched).toBe(0);
  expect(result.skipped).toBe(0);
});

// --------------------------------------------------------- semanticSearch

test("semanticSearch matches a memory and says which one it matched", async () => {
  const t = newHarness();
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  await t.run(async (ctx) => {
    // The person's own averaged vector is orthogonal to the query: only the
    // memory should pull them into the results.
    const personId = await ctx.db.insert("people", {
      userId: me.userId,
      name: "Ada Lovelace",
      updatedAt: 1,
      embedding: unitVector(1),
      embeddedText: "person",
    });
    await ctx.db.insert("memories", {
      userId: me.userId,
      personId,
      text: "works on an infinite-context-window database",
      createdAt: 1,
      embedding: unitVector(0),
      embeddedText: "memory",
    });
    // Same vector, another user: the userId filter must exclude it.
    const impostorId = await ctx.db.insert("people", {
      userId: other.userId,
      name: "Impostor",
      updatedAt: 1,
    });
    await ctx.db.insert("memories", {
      userId: other.userId,
      personId: impostorId,
      text: "also databases",
      createdAt: 1,
      embedding: unitVector(0),
      embeddedText: "memory",
    });
  });
  stubEmbedding(unitVector(0));

  const results = await me.as.action(api.people.semanticSearch, {
    query: "anyone with database experience",
  });

  expect(results.map((r) => r.name)).toEqual(["Ada Lovelace"]);
  expect(results[0].evidence).toBe(
    "works on an infinite-context-window database",
  );
  expect(results[0].score).toBeGreaterThan(0.9);
});

test("semanticSearch keeps a person's best score and never lists them twice", async () => {
  const t = newHarness();
  const me = await asNewUser(t);

  await t.run(async (ctx) => {
    const personId = await ctx.db.insert("people", {
      userId: me.userId,
      name: "Ada Lovelace",
      updatedAt: 1,
      embedding: unitVector(0),
      embeddedText: "person",
    });
    for (const text of ["weak memory", "the strong one"]) {
      await ctx.db.insert("memories", {
        userId: me.userId,
        personId,
        text,
        createdAt: 1,
        embedding: text === "the strong one" ? unitVector(0) : unitVector(1),
        embeddedText: text,
      });
    }
  });
  stubEmbedding(unitVector(0));

  const results = await me.as.action(api.people.semanticSearch, {
    query: "who is strong",
  });

  expect(results).toHaveLength(1);
  expect(results[0].evidence).toBe("the strong one");
});

test("semanticSearch leaves evidence unset when only the person vector matched", async () => {
  const t = newHarness();
  const me = await asNewUser(t);

  await t.run(async (ctx) => {
    await ctx.db.insert("people", {
      userId: me.userId,
      name: "Ada Lovelace",
      updatedAt: 1,
      embedding: unitVector(0),
      embeddedText: "person",
    });
  });
  stubEmbedding(unitVector(0));

  const results = await me.as.action(api.people.semanticSearch, {
    query: "who is ada",
  });

  expect(results.map((r) => r.name)).toEqual(["Ada Lovelace"]);
  expect(results[0].evidence).toBeUndefined();
});
