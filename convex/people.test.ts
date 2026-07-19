/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

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
