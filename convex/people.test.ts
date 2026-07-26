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

// ----------------------------------------------------- structured attributes

test("addPerson stores city, company, and role and returns them from getPerson", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const id = await as.mutation(api.people.addPerson, {
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
    as.mutation(api.people.addPerson, { name: "Mai", company: "  " }),
  ).rejects.toThrow("Company cannot be blank");
  await expect(
    as.mutation(api.people.addPerson, { name: "Mai", city: { name: " " } }),
  ).rejects.toThrow("City cannot be blank");
});

// ---------------------------------------------------------- contact handles

test("addPerson stores contact handles and a preferred platform", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const id = await as.mutation(api.people.addPerson, {
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
  expect(person?.contactHandles).toEqual([
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
    as.mutation(api.people.addPerson, {
      name: "Mai",
      contactHandles: [
        { platform: "Instagram", value: "a" },
        { platform: "instagram", value: "b" },
      ],
    }),
  ).rejects.toThrow("Keep one handle per platform");

  await expect(
    as.mutation(api.people.addPerson, {
      name: "Mai",
      contactHandles: [{ platform: "instagram", value: "a" }],
      preferredPlatform: "telegram",
    }),
  ).rejects.toThrow("Choose a preferred platform you have a handle for");

  await expect(
    as.mutation(api.people.addPerson, {
      name: "Mai",
      contactHandles: Array.from({ length: 9 }, (_, i) => ({
        platform: `platform${i}`,
        value: "x",
      })),
    }),
  ).rejects.toThrow("Keep at most 8 contact handles");
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

  const id = await as.mutation(api.people.addPerson, {
    name: "Mai",
    photoStorageId,
  });
  const person = await as.query(api.people.getPerson, { id });
  expect(person?.photoUrl).toEqual(expect.any(String));

  // A person without a photo answers null, so the client never guesses.
  const bareId = await as.mutation(api.people.addPerson, { name: "Vy" });
  const bare = await as.query(api.people.getPerson, { id: bareId });
  expect(bare?.photoUrl).toBeNull();
});

test("addPerson rejects a non-image photo without writing a person", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const blobId = await seedPhoto(t, "text/plain");

  await expect(
    as.mutation(api.people.addPerson, { name: "Mai", photoStorageId: blobId }),
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
  const id = await as.mutation(api.people.addPerson, {
    name: "Mai Tran",
    context: "met at the coffee meetup",
    company: "LinkedIn",
    city: { name: "Da Nang" },
  });

  vi.advanceTimersByTime(1000);
  const before = await t.run((ctx) => ctx.db.get("people", id));

  const edited = await as.mutation(api.people.editPerson, {
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
  const id = await as.mutation(api.people.addPerson, { name: "Maya Chen" });

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
  const id = await as.mutation(api.people.addPerson, { name: "Mai" });
  await expect(
    as.mutation(api.people.editPerson, { id, name: "  " }),
  ).rejects.toThrow("Name is required");
});

test("editPerson keeps the preferred pointer consistent with the handles", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const id = await as.mutation(api.people.addPerson, {
    name: "Mai",
    contactHandles: [
      { platform: "instagram", value: "mai.makes" },
      { platform: "whatsapp", value: "+84 90 123 4567" },
    ],
    preferredPlatform: "whatsapp",
  });

  // Replacing the list without the preferred platform clears the pointer
  // instead of dangling it.
  const afterDrop = await as.mutation(api.people.editPerson, {
    id,
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });
  expect(afterDrop.preferredPlatform).toBeUndefined();

  // Choosing a preferred platform that has no handle is refused.
  await expect(
    as.mutation(api.people.editPerson, { id, preferredPlatform: "telegram" }),
  ).rejects.toThrow("Choose a preferred platform you have a handle for");

  const afterPick = await as.mutation(api.people.editPerson, {
    id,
    preferredPlatform: "Instagram",
  });
  expect(afterPick.preferredPlatform).toBe("instagram");
});

test("editPerson swaps the photo and deletes the replaced blob", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const firstPhoto = await seedPhoto(t);
  const id = await as.mutation(api.people.addPerson, {
    name: "Mai",
    photoStorageId: firstPhoto,
  });

  const secondPhoto = await seedPhoto(t);
  const swapped = await as.mutation(api.people.editPerson, {
    id,
    photoStorageId: secondPhoto,
  });
  expect(swapped.photoUrl).toEqual(expect.any(String));
  // The replaced blob is gone for good -- this commit path CAN delete.
  expect(
    await t.run((ctx) => ctx.db.system.get("_storage", firstPhoto)),
  ).toBeNull();

  // Clearing the photo also deletes the blob it dereferences.
  const cleared = await as.mutation(api.people.editPerson, {
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
  const id = await as.mutation(api.people.addPerson, {
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

  const a = await me.as.mutation(api.people.addPerson, { name: "An" });
  vi.advanceTimersByTime(1000);
  await me.as.mutation(api.people.addPerson, { name: "Binh" });
  vi.advanceTimersByTime(1000);
  await me.as.mutation(api.people.addPerson, { name: "Chi" });
  await other.as.mutation(api.people.addPerson, { name: "Rao" });

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

  await me.as.mutation(api.people.addPerson, {
    name: "An Vo",
    context: "wore a Spain shirt, works on the research team, talked soccer",
    company: "Amazon",
  });
  await me.as.mutation(api.people.addPerson, {
    name: "Binh Le",
    context: "recruiter, met at the rooftop mixer",
    company: "LinkedIn",
  });
  // Same keyword in another user's note must never surface here.
  await other.as.mutation(api.people.addPerson, {
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

  await as.mutation(api.people.addPerson, {
    name: "An Vo",
    context: "talked soccer at the meetup",
    company: "Amazon",
  });
  await as.mutation(api.people.addPerson, {
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

  await as.mutation(api.people.addPerson, {
    name: "An Vo",
    company: "LinkedIn",
    city: { name: "San Francisco" },
  });
  await as.mutation(api.people.addPerson, {
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
  await as.mutation(api.people.addPerson, { name: "An" });
  vi.advanceTimersByTime(1000);
  await as.mutation(api.people.addPerson, { name: "Binh" });

  const hits = await as.query(api.people.searchDirectory, {});
  expect(hits.map((p) => p.name)).toEqual(["Binh", "An"]);
});

test("searchDirectory keyword also matches names and card text", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  await as.mutation(api.people.addPerson, {
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

  await me.as.mutation(api.people.addPerson, {
    name: "A",
    company: "LinkedIn",
    city: { name: "S\u00e0i G\u00f2n" },
  });
  vi.advanceTimersByTime(1000);
  await me.as.mutation(api.people.addPerson, {
    name: "B",
    company: "linkedin",
    role: "Recruiter",
  });
  vi.advanceTimersByTime(1000);
  await me.as.mutation(api.people.addPerson, {
    name: "C",
    company: "Amazon",
    city: { name: "Sai Gon" },
  });
  await other.as.mutation(api.people.addPerson, { name: "D", company: "Photon" });

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
  const id = await as.mutation(api.people.addPerson, {
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
  const otherId = await other.as.mutation(api.people.addPerson, { name: "Rao" });

  await expect(
    me.as.mutation(api.people.editPerson, { id: otherId, context: "x" }),
  ).rejects.toThrow("Person not found");
  await expect(
    t.mutation(api.people.editPerson, { id: otherId, context: "x" }),
  ).rejects.toThrow("Not signed in");

  const myId = await me.as.mutation(api.people.addPerson, { name: "Mai" });
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
  expect(person?.contactHandles).toEqual([
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
  expect(again).toEqual({ status: "already", personId: first.personId });

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
  const personId = await as.mutation(api.people.addPerson, {
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
  expect(result).toEqual({ status: "attached", personId });

  const person = await as.query(api.people.getPerson, { id: personId });
  expect(person?.contactHandles).toEqual([
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
  expect(dedup).toEqual({ status: "already", personId });
});

test("saveSharedProfile refuses to attach a second handle on a platform the person already has", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const personId = await as.mutation(api.people.addPerson, {
    name: "Mai Tr\u1ea7n",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });

  await expect(
    as.mutation(api.people.saveSharedProfile, {
      ...sharedProfile,
      handleValue: "mai.ceramics",
      profileUrl: "https://instagram.com/mai.ceramics",
      attachToPersonId: personId,
    }),
  ).rejects.toThrow("Keep one handle per platform");

  const person = await as.query(api.people.getPerson, { id: personId });
  expect(person?.contactHandles).toEqual([
    { platform: "instagram", value: "mai.makes" },
  ]);
});

test("saveSharedProfile creates a person when the attach target is gone or not the caller's", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  // The extension's mirror can be days stale; a capture must never be lost.
  const deletedId = await me.as.mutation(api.people.addPerson, { name: "Mai" });
  await me.as.mutation(api.people.deletePerson, { personId: deletedId });

  const fromDeleted = await me.as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    attachToPersonId: deletedId,
  });
  expect(fromDeleted.status).toBe("created");
  expect(fromDeleted.personId).not.toBe(deletedId);

  const theirId = await other.as.mutation(api.people.addPerson, { name: "Rao" });
  const fromTheirs = await me.as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    handleValue: "mai.ceramics",
    profileUrl: "https://instagram.com/mai.ceramics",
    attachToPersonId: theirId,
  });
  expect(fromTheirs.status).toBe("created");
  expect(fromTheirs.personId).not.toBe(theirId);
  expect(
    (await other.as.query(api.people.getPerson, { id: theirId }))
      ?.contactHandles,
  ).toBeUndefined();
});

test("saveSharedProfile lets handle identity beat the attach target", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const mai = await as.mutation(api.people.addPerson, {
    name: "Mai Tr\u1ea7n",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });
  const binh = await as.mutation(api.people.addPerson, { name: "Binh Le" });

  const result = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    attachToPersonId: binh,
  });
  expect(result).toEqual({ status: "already", personId: mai });

  // Binh never gains an account that is provably somebody else's.
  expect(
    (await as.query(api.people.getPerson, { id: binh }))?.contactHandles,
  ).toBeUndefined();
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
  expect(result).toEqual({ status: "attached", personId });

  const person = await as.query(api.people.getPerson, { id: personId });
  expect(person?.context).toBe("met at the ceramics market");
  expect(person?.contactHandles).toHaveLength(1);

  // A genuinely different account on that platform is still refused.
  await expect(
    as.mutation(api.people.saveSharedProfile, {
      ...sharedProfile,
      handleValue: "mai.ceramics",
      profileUrl: "https://instagram.com/mai.ceramics",
      attachToPersonId: personId,
    }),
  ).rejects.toThrow("Keep one handle per platform");
});

test("saveSharedProfile keeps the shared URL on a person that has none", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const personId = await as.mutation(api.people.addPerson, {
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
  expect(attached).toEqual({ status: "attached", personId });
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
  expect(again).toEqual({ status: "already", personId });
  expect((await as.query(api.people.getPerson, { id: personId }))?.link).toBe(
    "https://www.linkedin.com/in/mai-tran-8a91b2",
  );
});

test("saveSharedProfile gives a re-shared person the URL they were saved without", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const personId = await as.mutation(api.people.addPerson, {
    name: "Mai Tr\u1ea7n",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });

  const result = await as.mutation(api.people.saveSharedProfile, sharedProfile);
  expect(result).toEqual({ status: "already", personId });
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
  expect(person?.contactHandles).toEqual([
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

test("saveSharedProfile rejects blank fields and an over-long appended note", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

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
  await expect(
    as.mutation(api.people.saveSharedProfile, {
      ...sharedProfile,
      note: "x".repeat(4001),
    }),
  ).rejects.toThrow("Context is too long");

  const saved = await as.mutation(api.people.saveSharedProfile, {
    ...sharedProfile,
    note: "x".repeat(4000),
  });
  // The append is capped on the combined length, not the typed one.
  await expect(
    as.mutation(api.people.saveSharedProfile, { ...sharedProfile, note: "y" }),
  ).rejects.toThrow("Context is too long");
  const person = await t.run((ctx) => ctx.db.get("people", saved.personId));
  expect(person?.context).toHaveLength(4000);
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
  const personId = await as.mutation(api.people.addPerson, {
    name: "Mai Tr\u1ea7n",
    contactHandles: [{ platform: " Instagram ", value: "@mai.makes" }],
  });

  const result = await as.mutation(api.people.saveSharedProfile, sharedProfile);
  expect(result).toEqual({ status: "already", personId });
});

test("editPerson rewrites the handle index in both directions", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const personId = await as.mutation(api.people.addPerson, {
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
  expect(dedup).toEqual({ status: "already", personId });
});

test("deletePerson frees the handle for a later share", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const personId = await as.mutation(api.people.addPerson, {
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
): Promise<number> {
  let cursor: string | null = null;
  let patched = 0;
  for (let page = 0; page < 20; page++) {
    // Annotated because the cursor fed back in would otherwise make the
    // inferred result type circular.
    const result: { patched: number; isDone: boolean; cursor: string } =
      await t.mutation(internal.people.backfillPersonHandles, { cursor });
    patched += result.patched;
    if (result.isDone) {
      return patched;
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

  expect(await drainPersonHandlesBackfill(t)).toBe(1);
  const shared = await as.mutation(api.people.saveSharedProfile, sharedProfile);
  expect(shared).toEqual({ status: "already", personId: legacyId });

  // Idempotent: a second run has nothing left to index.
  expect(await drainPersonHandlesBackfill(t)).toBe(0);
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

  expect(await drainPersonHandlesBackfill(t)).toBe(total);
  expect(
    await t.run((ctx) => ctx.db.query("personHandles").collect()),
  ).toHaveLength(total);
});
