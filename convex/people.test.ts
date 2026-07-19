/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { normalizeName } from "./nameSearch";

const modules = import.meta.glob("./**/*.ts");

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
function stubEmbeddingsSequence(
  respond: (callIndex: number) => Response,
): { callCount: () => number } {
  const realFetch = globalThis.fetch;
  let calls = 0;
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
        const response = respond(calls);
        calls++;
        return response;
      }
      return realFetch(input, init);
    },
  );
  return { callCount: () => calls };
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

test("addPerson creates a person owned by the caller with a timestamp", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);

  const id = await as.mutation(api.people.addPerson, { name: "Maya Chen" });

  const person = await t.run((ctx) => ctx.db.get("people", id));
  expect(person?.name).toBe("Maya Chen");
  expect(person?.userId).toBe(userId);
  expect(typeof person?.updatedAt).toBe("number");
});

test("addPerson rejects a blank name", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await expect(
    as.mutation(api.people.addPerson, { name: "   " }),
  ).rejects.toThrow("Name is required");
});

test("addPerson rejects an unauthenticated caller", async () => {
  const t = convexTest(schema, modules);
  await expect(
    t.mutation(api.people.addPerson, { name: "Maya" }),
  ).rejects.toThrow("Not signed in");
});

test("searchPeople matches the caller's people by name and excludes others", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  await me.as.mutation(api.people.addPerson, { name: "Maya Chen" });
  await me.as.mutation(api.people.addPerson, { name: "Felix Ng" });
  await other.as.mutation(api.people.addPerson, { name: "Maya Rao" });

  const results = await me.as.query(api.people.searchPeople, { query: "Maya" });
  expect(results.map((p) => p.name)).toEqual(["Maya Chen"]);
});

test("searchPeople with an empty query returns only the caller's recent people", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  await me.as.mutation(api.people.addPerson, { name: "Maya Chen" });
  await me.as.mutation(api.people.addPerson, { name: "Felix Ng" });
  // Another user's person must never appear in my empty-query results.
  await other.as.mutation(api.people.addPerson, { name: "Rao" });

  const results = await me.as.query(api.people.searchPeople, { query: "  " });
  expect(results.map((p) => p.name).sort()).toEqual(["Felix Ng", "Maya Chen"]);
});

test("getPerson returns the caller's person and null for another user's", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  const myId = await me.as.mutation(api.people.addPerson, { name: "Maya" });
  const otherId = await other.as.mutation(api.people.addPerson, {
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
  const id = await me.as.mutation(api.people.addPerson, { name: "Maya" });
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
  const otherId = await other.as.mutation(api.people.addPerson, {
    name: "Rao",
  });

  await expect(
    me.as.mutation(api.people.updatePerson, { id: otherId, context: "x" }),
  ).rejects.toThrow("Person not found");
});

test("updatePerson with omitted fields clears them (undefined unsets)", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const id = await me.as.mutation(api.people.addPerson, { name: "Maya" });
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
  const id = await me.as.mutation(api.people.addPerson, { name: "Maya" });

  await expect(t.mutation(api.people.addPerson, { name: "x" })).rejects.toThrow(
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

  const id = await as.mutation(api.people.addPerson, { name: "Maya Chen" });
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
  const otherId = await other.as.mutation(api.people.addPerson, {
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
  await as.mutation(api.people.addPerson, { name: "Maya" });

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
    await as.mutation(api.people.addPerson, { name: `Person ${i}` });
  }
  await expect(
    as.mutation(api.people.addPerson, { name: "One too many" }),
  ).rejects.toThrow("Too many requests -- please wait a moment");

  vi.setSystemTime(Date.now() + 60_000);
  await expect(
    as.mutation(api.people.addPerson, { name: "A new window" }),
  ).resolves.toBeTypeOf("string");
});

test("updatePerson is rate-limited per caller (wiring check)", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const id = await as.mutation(api.people.addPerson, { name: "Maya" });
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
  await as.mutation(api.people.addPerson, { name: "Nguy\u1ec5n V\u0103n D\u0169ng" });

  const results = await as.query(api.people.searchPeople, { query: "dung" });
  expect(results.map((p) => p.name)).toEqual(["Nguy\u1ec5n V\u0103n D\u0169ng"]);
});

test("searchPeople finds an unaccented name via an accented query", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await as.mutation(api.people.addPerson, { name: "Dung" });

  const results = await as.query(api.people.searchPeople, {
    query: "D\u0169ng",
  });
  expect(results.map((p) => p.name)).toEqual(["Dung"]);
});

test("searchPeople finds the D-stroke name via a plain-D query", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await as.mutation(api.people.addPerson, { name: "\u0110un \u0110un" });

  const results = await as.query(api.people.searchPeople, { query: "dun" });
  expect(results.map((p) => p.name)).toEqual(["\u0110un \u0110un"]);
});

test("searchPeople keeps user isolation on the normalized-name index", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  await me.as.mutation(api.people.addPerson, { name: "D\u0169ng" });
  await other.as.mutation(api.people.addPerson, { name: "D\u0169ng Two" });

  const results = await me.as.query(api.people.searchPeople, { query: "dung" });
  expect(results.map((p) => p.name)).toEqual(["D\u0169ng"]);
});

test("searchPeople with a query that normalizes to empty falls back to recent people", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await as.mutation(api.people.addPerson, { name: "Maya Chen" });

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
  const stub = stubEmbeddingsSequence((callIndex) =>
    callIndex === 0
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
  expect(stub.callCount()).toBe(2);

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
    as.mutation(api.people.addPerson, {
      name: "Maya",
      context: "x".repeat(4001),
    }),
  ).rejects.toThrow("Context is too long -- keep it under 4000 characters");
});

test("addPerson accepts context at exactly 4000 characters", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await as.mutation(api.people.addPerson, {
    name: "Maya",
    context: "x".repeat(4000),
  });
  const person = await t.run((ctx) => ctx.db.get("people", id));
  expect(person?.context).toHaveLength(4000);
});

test("updatePerson rejects context over 4000 characters", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await as.mutation(api.people.addPerson, { name: "Maya" });
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
  const stub = stubEmbeddingsSequence((callIndex) =>
    callIndex === 0
      ? new Response("rate limited", { status: 429 })
      : Response.json({ data: [{ embedding: new Array(1536).fill(0.1) }] }),
  );

  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await as.mutation(api.people.addPerson, { name: "Maya Chen" });

  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const stored = await t.run((ctx) => ctx.db.get("people", id));
  expect(stored?.embedding).toBeDefined();
  expect(stub.callCount()).toBe(2);
});

test("embed gives up after 3 total attempts without throwing", async () => {
  const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
  const stub = stubEmbeddingsSequence(
    () => new Response("boom", { status: 500 }),
  );

  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await as.mutation(api.people.addPerson, { name: "Maya Chen" });

  await expect(
    t.finishAllScheduledFunctions(vi.runAllTimers),
  ).resolves.not.toThrow();

  const stored = await t.run((ctx) => ctx.db.get("people", id));
  expect(stored?.embedding).toBeUndefined();
  expect(stub.callCount()).toBe(3);
  expect(consoleError).toHaveBeenCalled();

  consoleError.mockRestore();
});
