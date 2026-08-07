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

// Both accept mutations now return a creation outcome, not a bare id
// (identity brief, task 3: captures routes through the same owner check
// addPerson does). Most tests here exist to exercise something else and
// expect a fresh person, so this unwraps that common case and throws loudly
// if a fixture unexpectedly collides with an existing handle instead.
async function acceptCaptureId(
  as: TestConvexForDataModel<TestDataModel>,
  args: FunctionArgs<typeof api.captures.acceptCapture>,
): Promise<Id<"people">> {
  const result = await as.mutation(api.captures.acceptCapture, args);
  if (result.status !== "created") {
    throw new Error(`acceptCaptureId: expected created, got ${result.status}`);
  }
  return result.personId;
}

// Strips provenance (source, platformId, addedAt) so tests about handle
// mechanics can keep asserting on platform and value alone. Tests about
// provenance itself compare the full shape directly instead of going
// through this.
function displayOnly(
  handles: Array<{ platform: string; value: string }> | undefined,
): Array<{ platform: string; value: string }> | undefined {
  return handles?.map(({ platform, value }) => ({ platform, value }));
}

async function acceptManualCaptureId(
  as: TestConvexForDataModel<TestDataModel>,
  args: FunctionArgs<typeof api.captures.acceptManualCapture>,
): Promise<Id<"people">> {
  const result = await as.mutation(api.captures.acceptManualCapture, args);
  if (result.status !== "created") {
    throw new Error(
      `acceptManualCaptureId: expected created, got ${result.status}`,
    );
  }
  return result.personId;
}

// convex-test's storage mock never records contentType from the Blob it was
// given (its storeBlob syscall only stores size and sha256), so real
// upload-validation code always sees contentType === undefined here. Patch
// the system table directly, bypassing the DataModel table-name type (a
// system table isn't one of ours), so tests can exercise that validation.
async function setStoredContentType(
  t: ReturnType<typeof convexTest>,
  id: unknown,
  contentType: string,
) {
  await t.run((ctx) => (ctx.db as any).patch("_storage", id, { contentType }));
}

async function seedScreenshot(
  t: ReturnType<typeof convexTest>,
  contentType = "image/png",
) {
  const id = await t.run(async (ctx) =>
    ctx.storage.store(new Blob(["fake-image"], { type: contentType })),
  );
  await setStoredContentType(t, id, contentType);
  return id;
}

async function seedOversizedScreenshot(t: ReturnType<typeof convexTest>) {
  const id = await t.run(async (ctx) =>
    ctx.storage.store(
      new Blob([new Uint8Array(10 * 1024 * 1024 + 1)], { type: "image/png" }),
    ),
  );
  await setStoredContentType(t, id, "image/png");
  return id;
}

const EXTRACTION = {
  is_profile: true,
  platform: "x",
  name: "Ada Lovelace",
  handle: "@ada_l",
  headline: "Compiler engineer",
  bio: "Building symbolic math tools.",
};

// A deterministic 1536-dim unit vector with a 1 at the given position.
function unitVector(hotIndex: number): number[] {
  const vector = new Array(1536).fill(0);
  vector[hotIndex] = 1;
  return vector;
}

// Stub the two OpenAI endpoints, routed by pathname. Anything to a
// different host (convex-test internals, storage URLs) falls through to
// the real fetch; anything to the OpenAI host that isn't one of our two
// known paths throws instead of silently reaching the real API -- a typo'd
// path here should fail loudly in tests, not go out over the network.
function stubOpenAI(options: {
  extraction?: unknown;
  embedding?: number[];
  failExtraction?: boolean;
}) {
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
      if (url.hostname !== "api.openai.com") {
        return realFetch(input, init);
      }
      if (url.pathname.includes("/chat/completions")) {
        if (options.failExtraction) {
          return new Response("upstream error", { status: 500 });
        }
        return Response.json({
          choices: [
            { message: { content: JSON.stringify(options.extraction) } },
          ],
        });
      }
      if (url.pathname.includes("/embeddings")) {
        return Response.json({
          data: [{ embedding: options.embedding ?? unitVector(0) }],
        });
      }
      throw new Error(`Unstubbed OpenAI request: ${url.pathname}`);
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

test("createCapture extracts a profile in the background", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);

  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const capture = await t.run((ctx) => ctx.db.get("captures", captureId));
  expect(capture?.status).toBe("ready");
  expect(capture?.extracted).toMatchObject({
    platform: "x",
    name: "Ada Lovelace",
    handle: "@ada_l",
  });
});

test("a screenshot that is not a profile fails calmly", async () => {
  stubOpenAI({ extraction: { ...EXTRACTION, is_profile: false } });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);

  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const capture = await t.run((ctx) => ctx.db.get("captures", captureId));
  expect(capture?.status).toBe("failed");
  expect(capture?.error).toBe("Could not read a profile in this screenshot");
});

test("an upstream failure marks the capture failed, not stuck pending", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);

  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const capture = await t.run((ctx) => ctx.db.get("captures", captureId));
  expect(capture?.status).toBe("failed");
});

test("listCaptures returns only the caller's captures, with image urls", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  await me.as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await other.as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const mine = await me.as.query(api.captures.listCaptures, {});
  expect(mine).toHaveLength(1);
  expect(typeof mine[0].imageUrl).toBe("string");
});

test("acceptCapture creates an owned person and consumes the capture", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const personId = await acceptCaptureId(as, {
    captureId,
    link: "https://x.com/ada_l",
    context: "Met at the meetup.",
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person).toMatchObject({
    userId,
    name: "Ada Lovelace",
    link: "https://x.com/ada_l",
    context: "Met at the meetup.",
    platform: "x",
    handle: "@ada_l",
    screenshotId,
  });
  // Embedding was computed in the background from the person's text.
  expect(person?.embedding).toHaveLength(1536);
  expect(await t.run((ctx) => ctx.db.get("captures", captureId))).toBeNull();

  // The insert bypasses addPerson, so it must feed the keyword index itself
  // -- same reasoning as the normalizedName it already writes.
  const hits = await as.query(api.people.searchDirectory, {
    keyword: "meetup",
  });
  expect(hits.map((p) => p.name)).toEqual(["Ada Lovelace"]);
});

// Lenient where acceptManualCapture is strict: nobody is present to fix an
// OCR miss, so a phone/whatsapp value with no digit at all is dropped rather
// than thrown -- the person still lands, just without a handle the fold
// could otherwise collide two strangers on (handleKeys.ts's hasPhoneDigit).
//
// X2a: the drop has to be total, not just contactHandles/personHandles.
// person.platform/person.handle are the legacy scalars backfillLegacyHandles
// (people.ts) reads to fold INTO the identity index later -- writing the
// dropped value there anyway would let a future run of that migration
// recreate the exact collision this gate exists to prevent, through a
// completely different code path.
test("acceptCapture drops a digitless extracted phone value and flags handleDropped", async () => {
  stubOpenAI({ extraction: { ...EXTRACTION, platform: "phone", handle: "unknown" } });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const result = await as.mutation(api.captures.acceptCapture, { captureId });
  expect(result.status).toBe("created");
  if (result.status !== "created") throw new Error("unreachable");
  expect(result.handleDropped).toBe(true);

  const person = await t.run((ctx) => ctx.db.get("people", result.personId));
  expect(person?.contactHandles).toBeUndefined();
  expect(person?.platform).toBeUndefined();
  expect(person?.handle).toBeUndefined();
  expect(await handleRows(t)).toEqual([]);
});

// The reviewer's exact scenario (identity brief, R1): a legacy row written
// before this gate existed still has a digitless phone value indexed under
// its lowercase fold ("unknown"). A second stranger's own unreadable OCR
// read ("Unknown", same fold) must not attach to that legacy row just
// because the two happen to collide on the same fallback key -- the drop
// above is what keeps a NEW digitless read from ever reaching that lookup
// at all.
test("a legacy person's digitless phone value does not attach a new capture's own digitless read", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const alice = await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Alice",
      normalizedName: "alice",
      contactHandles: [{ platform: "phone", value: "unknown" }],
      updatedAt: Date.now(),
    }),
  );
  await t.run((ctx) =>
    ctx.db.insert("personHandles", {
      userId,
      personId: alice,
      platform: "phone",
      valueKey: "unknown",
    }),
  );

  stubOpenAI({ extraction: { ...EXTRACTION, platform: "phone", handle: "Unknown" } });
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const result = await as.mutation(api.captures.acceptCapture, { captureId });
  expect(result.status).toBe("created");
  if (result.status !== "created") throw new Error("unreachable");
  expect(result.handleDropped).toBe(true);
  // Bob, not Alice.
  expect(result.personId).not.toBe(alice);

  const bob = await t.run((ctx) => ctx.db.get("people", result.personId));
  expect(bob?.contactHandles).toBeUndefined();
  // Bob's own legacy scalars stay clear too (X2a) -- otherwise a future
  // backfillLegacyHandles run over Bob's row could still fold "Unknown"
  // into the index and recreate this exact collision through that path.
  expect(bob?.platform).toBeUndefined();
  expect(bob?.handle).toBeUndefined();
  // Alice's own row is untouched, and still the only one "unknown" indexes.
  const rows = await t.run((ctx) => ctx.db.query("personHandles").collect());
  expect(rows).toEqual([expect.objectContaining({ personId: alice, valueKey: "unknown" })]);
});

test("acceptCapture keeps the extracted bio and makes it searchable", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const personId = await acceptCaptureId(as, { captureId });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  // The bio is the richest text the extraction paid for -- what the person
  // says they are about. Dropping it at accept would leave them invisible to
  // every "who do I know who does X" search.
  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person?.bio).toBe("Building symbolic math tools.");
  const hits = await as.query(api.people.searchDirectory, {
    keyword: "symbolic",
  });
  expect(hits.map((p) => p.name)).toEqual(["Ada Lovelace"]);
});

test("an event capture links its accepted person to that event", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
    event: {
      clientKey: "capture-event",
      title: "Design meetup",
      startedAt: 6_000,
    },
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const personId = await acceptCaptureId(as, { captureId });

  expect(await as.query(api.events.listForPerson, { personId })).toMatchObject([
    { title: "Design meetup", startedAt: 6_000 },
  ]);
});

test("a manually named capture is findable by keyword search", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);
  // Not extracted yet: manual naming is allowed while the capture is still
  // pending, and the person it creates must be searchable all the same.
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });

  await as.mutation(api.captures.acceptManualCapture, {
    captureId,
    name: "Vy Ho",
    context: "runs the pho place in district 3",
  });

  const hits = await as.query(api.people.searchDirectory, { keyword: "pho" });
  expect(hits.map((p) => p.name)).toEqual(["Vy Ho"]);
});

test("another user cannot accept or discard my capture", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  const captureId = await me.as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await expect(
    other.as.mutation(api.captures.acceptCapture, { captureId }),
  ).rejects.toThrow("Capture not found");
  await expect(
    other.as.mutation(api.captures.discardCapture, { captureId }),
  ).rejects.toThrow("Capture not found");
});

test("discardCapture removes the capture and its file", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await as.mutation(api.captures.discardCapture, { captureId });

  expect(await t.run((ctx) => ctx.db.get("captures", captureId))).toBeNull();
  expect(
    await t.run((ctx) => ctx.storage.getUrl(screenshotId)),
  ).toBeNull();
});

test("semanticSearch finds my people by meaning and never another user's", async () => {
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  // Seed embeddings directly: person A matches the query vector exactly,
  // person B is orthogonal (filtered by score), and the other user's person
  // shares A's vector but must be excluded by the userId filter.
  await t.run(async (ctx) => {
    await ctx.db.insert("people", {
      userId: me.userId,
      name: "Ada Lovelace",
      context: "Compiler engineer from the meetup",
      updatedAt: 1,
      embedding: unitVector(0),
      embeddedText: "a",
    });
    await ctx.db.insert("people", {
      userId: me.userId,
      name: "Grace Hopper",
      updatedAt: 1,
      embedding: unitVector(1),
      embeddedText: "b",
    });
    await ctx.db.insert("people", {
      userId: other.userId,
      name: "Impostor",
      updatedAt: 1,
      embedding: unitVector(0),
      embeddedText: "c",
    });
  });

  stubOpenAI({ embedding: unitVector(0) });
  const results = await me.as.action(api.people.semanticSearch, {
    query: "who was the compiler person",
  });

  expect(results.map((r) => r.name)).toEqual(["Ada Lovelace"]);
  expect(results[0].score).toBeGreaterThan(0.9);
});

test("semanticSearch is rate-limited per caller (wiring check)", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  stubOpenAI({ embedding: unitVector(0) });

  await as.action(api.people.semanticSearch, { query: "anyone" });

  const window = await t.run((ctx) =>
    ctx.db
      .query("rateLimits")
      .withIndex("by_user_action", (q) =>
        q.eq("userId", userId).eq("action", "semanticSearch"),
      )
      .unique(),
  );
  expect(window?.count).toBe(1);
});

test("updatePerson refreshes the embedding from the new context", async () => {
  stubOpenAI({ embedding: unitVector(2) });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  const added = await as.mutation(api.people.addPersonWithOutcome, { name: "Maya", contactHandles: [{ platform: "phone", value: "unlisted1" }], context: "met before this test" });
  if (added.status !== "created") throw new Error("unreachable");
  const personId = added.personId;
  await as.mutation(api.people.updatePerson, {
    id: personId,
    context: "Runs the observatory",
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person?.embedding).toHaveLength(1536);
  expect(person?.embeddedText).toBe("Maya\nRuns the observatory");
});

// ------------------------------------------------------- upload validation

// Note: we don't assert the blob is gone here. Convex mutations are one
// atomic transaction -- the storage.delete() call in createCapture runs in
// the same transaction as the throw that follows it, so convex-test's
// simulated storage (backed by the same transactional _storage table) rolls
// the delete back along with everything else. The security-relevant
// property this test guards is that a bad upload never becomes a capture
// row or a scheduled extraction call, which does hold regardless.
test("createCapture rejects a non-image upload", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t, "application/pdf");

  await expect(
    as.mutation(api.captures.createCapture, { screenshotId }),
  ).rejects.toThrow("Please upload an image under 10 MB");

  expect(await as.query(api.captures.listCaptures, {})).toHaveLength(0);
});

test("createCapture rejects an oversized upload", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedOversizedScreenshot(t);

  await expect(
    as.mutation(api.captures.createCapture, { screenshotId }),
  ).rejects.toThrow("Please upload an image under 10 MB");

  expect(await as.query(api.captures.listCaptures, {})).toHaveLength(0);
});

test("createCapture accepts a small, valid image", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t, "image/png");

  await expect(
    as.mutation(api.captures.createCapture, { screenshotId }),
  ).resolves.toBeTypeOf("string");
});

// ---------------------------------------------------------------- retry

test("retryExtract reruns extraction on a failed capture", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(
    (await t.run((ctx) => ctx.db.get("captures", captureId)))?.status,
  ).toBe("failed");

  stubOpenAI({ extraction: EXTRACTION });
  await as.mutation(api.captures.retryExtract, { captureId });
  expect(
    (await t.run((ctx) => ctx.db.get("captures", captureId)))?.status,
  ).toBe("pending");

  await t.finishAllScheduledFunctions(vi.runAllTimers);
  const capture = await t.run((ctx) => ctx.db.get("captures", captureId));
  expect(capture?.status).toBe("ready");
  expect(capture?.error).toBeUndefined();
  expect(capture?.errorDetail).toBeUndefined();
});

test("retryExtract throttles a burst past the per-minute limit", async () => {
  // Every retry re-runs the paid extraction, so it carries its own
  // denial-of-wallet budget separate from createCapture's.
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  for (let i = 0; i < 10; i++) {
    await as.mutation(api.captures.retryExtract, { captureId });
    // The stub keeps failing, so the capture returns to "failed" and
    // stays retryable for the next loop iteration.
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  }
  await expect(
    as.mutation(api.captures.retryExtract, { captureId }),
  ).rejects.toThrow("Too many requests -- please wait a moment");

  vi.setSystemTime(Date.now() + 60_000);
  await as.mutation(api.captures.retryExtract, { captureId });
  expect(
    (await t.run((ctx) => ctx.db.get("captures", captureId)))?.status,
  ).toBe("pending");
});

test("retryExtract on a ready capture throws", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await expect(
    as.mutation(api.captures.retryExtract, { captureId }),
  ).rejects.toThrow("Capture is not ready to retry");
});

test("retryExtract rejects another user's capture", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  const captureId = await me.as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await expect(
    other.as.mutation(api.captures.retryExtract, { captureId }),
  ).rejects.toThrow("Capture not found");
});

// ------------------------------------------------------- error sanitization

test("an upstream failure never leaks raw error text to the user", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const capture = await t.run((ctx) => ctx.db.get("captures", captureId));
  expect(capture?.error).toBe("Could not read this screenshot -- you can retry");
  expect(capture?.error?.toLowerCase()).not.toContain("api");
  expect(capture?.error?.toLowerCase()).not.toContain("env");
  // The raw detail is kept server-side...
  expect(capture?.errorDetail).toContain("upstream error");
  // ...but never reaches a client response.
  const listed = await as.query(api.captures.listCaptures, {});
  expect(listed[0]).not.toHaveProperty("errorDetail");
});

test("the not-a-profile message passes through as-is (it is already safe)", async () => {
  stubOpenAI({ extraction: { ...EXTRACTION, is_profile: false } });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const capture = await t.run((ctx) => ctx.db.get("captures", captureId));
  expect(capture?.error).toBe("Could not read a profile in this screenshot");
  expect(capture?.errorDetail).toBeUndefined();
});

// -------------------------------------------------------- rate limiting

test("createCapture throttles a burst past the per-minute limit", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);

  for (let i = 0; i < 10; i++) {
    await as.mutation(api.captures.createCapture, {
      screenshotId: await seedScreenshot(t),
    });
  }
  await expect(
    as.mutation(api.captures.createCapture, {
      screenshotId: await seedScreenshot(t),
    }),
  ).rejects.toThrow("Too many requests -- please wait a moment");

  vi.setSystemTime(Date.now() + 60_000);
  await expect(
    as.mutation(api.captures.createCapture, {
      screenshotId: await seedScreenshot(t),
    }),
  ).resolves.toBeTypeOf("string");
});

test("createCapture also tracks a separate daily window", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);

  await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });

  const dayWindow = await t.run((ctx) =>
    ctx.db
      .query("rateLimits")
      .withIndex("by_user_action", (q) =>
        q.eq("userId", userId).eq("action", "createCapture:day"),
      )
      .unique(),
  );
  expect(dayWindow?.count).toBe(1);
});

test("rate limits are per user: exhausting mine does not affect another user", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);

  for (let i = 0; i < 10; i++) {
    await me.as.mutation(api.captures.createCapture, {
      screenshotId: await seedScreenshot(t),
    });
  }
  await expect(
    me.as.mutation(api.captures.createCapture, {
      screenshotId: await seedScreenshot(t),
    }),
  ).rejects.toThrow("Too many requests -- please wait a moment");

  await expect(
    other.as.mutation(api.captures.createCapture, {
      screenshotId: await seedScreenshot(t),
    }),
  ).resolves.toBeTypeOf("string");
});

// ------------------------------------------------------------ unauth

test("captures functions reject an unauthenticated caller", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const screenshotId = await seedScreenshot(t);
  // A real, existing captureId -- so arg validation passes and requireUser's
  // rejection (not a v.id() format error) is what we're actually testing.
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });

  await expect(t.mutation(api.captures.generateUploadUrl, {})).rejects.toThrow(
    "Not signed in",
  );
  await expect(
    t.mutation(api.captures.createCapture, { screenshotId }),
  ).rejects.toThrow("Not signed in");
  await expect(t.query(api.captures.listCaptures, {})).rejects.toThrow(
    "Not signed in",
  );
  await expect(
    t.mutation(api.captures.acceptCapture, { captureId }),
  ).rejects.toThrow("Not signed in");
  await expect(
    t.mutation(api.captures.acceptManualCapture, { captureId, name: "Ada" }),
  ).rejects.toThrow("Not signed in");
  await expect(
    t.mutation(api.captures.discardCapture, { captureId }),
  ).rejects.toThrow("Not signed in");
  await expect(
    t.mutation(api.captures.retryExtract, { captureId }),
  ).rejects.toThrow("Not signed in");
});

// -------------------------------------------------------- race / contract

test("discarding a capture before extraction finishes leaves nothing behind", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);

  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  // Discard races the scheduled extract action -- it runs before
  // finishAllScheduledFunctions lets that action execute.
  await as.mutation(api.captures.discardCapture, { captureId });

  await expect(t.finishAllScheduledFunctions(vi.runAllTimers)).resolves.not.toThrow();

  expect(await t.run((ctx) => ctx.db.get("captures", captureId))).toBeNull();
  const people = await t.run((ctx) => ctx.db.query("people").collect());
  expect(people).toHaveLength(0);

  // A stray finishExtract for the now-deleted capture must no-op, not throw.
  // extractedValidator has no is_profile field -- strip it from EXTRACTION.
  const { is_profile: _isProfile, ...extracted } = EXTRACTION;
  await expect(
    t.mutation(internal.captures.finishExtract, { captureId, extracted }),
  ).resolves.toBeNull();
});

test("acceptCapture is not reentrant: a second accept finds nothing to accept", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await as.mutation(api.captures.acceptCapture, { captureId });
  await expect(
    as.mutation(api.captures.acceptCapture, { captureId }),
  ).rejects.toThrow("Capture not found");

  const people = await t.run((ctx) => ctx.db.query("people").collect());
  expect(people).toHaveLength(1);
});

test("acceptCapture on a still-pending capture is rejected", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  // Deliberately not finishing the scheduled extraction -- still "pending".

  await expect(
    as.mutation(api.captures.acceptCapture, { captureId }),
  ).rejects.toThrow("Capture is not ready");
});

// ------------------------------------------------- manual triage (no OCR)

test("acceptManualCapture names a failed capture and consumes it", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(
    (await t.run((ctx) => ctx.db.get("captures", captureId)))?.status,
  ).toBe("failed");

  const personId = await acceptManualCaptureId(as, {
    captureId,
    name: "Ada Lovelace",
    headline: "Convex -- MIT",
    context: "Met at the meetup.",
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person).toMatchObject({
    userId,
    name: "Ada Lovelace",
    headline: "Convex -- MIT",
    context: "Met at the meetup.",
    // The screenshot moves to the person as a visual memory anchor.
    screenshotId,
  });
  // Embedding was computed in the background, same as acceptCapture.
  expect(person?.embedding).toHaveLength(1536);
  expect(await t.run((ctx) => ctx.db.get("captures", captureId))).toBeNull();
});

test("acceptManualCapture trims the surrounding whitespace of the name", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const personId = await acceptManualCaptureId(as, {
    captureId,
    name: "  Ada Lovelace  ",
  });
  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person?.name).toBe("Ada Lovelace");
});

test("accepted captures are findable by accent-insensitive search", async () => {
  // Both accept paths bypass addPerson, so they must write normalizedName
  // themselves or the person is invisible to the normalized search index.
  // The fixture is the Vietnamese D-stroke name (escaped to keep this
  // file ASCII) from the real network this app serves.
  const dStrokeName = "\u0110un \u0110un";
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  await as.mutation(api.captures.acceptManualCapture, {
    captureId,
    name: dStrokeName,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  const manual = await as.query(api.people.searchPeople, { query: "dun" });
  expect(manual.map((p) => p.name)).toContain(dStrokeName);

  // The AI path writes it too ("Ha Anh" with accents, escaped).
  const accentedName = "H\u00e0 Anh";
  stubOpenAI({
    extraction: { ...EXTRACTION, name: accentedName },
  });
  const aiCaptureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  await as.mutation(api.captures.acceptCapture, { captureId: aiCaptureId });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  const ai = await as.query(api.people.searchPeople, { query: "ha anh" });
  expect(ai.map((p) => p.name)).toContain(accentedName);
});

test("acceptManualCapture names a still-pending capture and survives the late extraction", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  // A stuck extraction must never block a human: name it while still pending.

  const personId = await acceptManualCaptureId(as, {
    captureId,
    name: "Grace Hopper",
  });

  // The in-flight extraction lands after the human already named them --
  // getCapture finds nothing, so finishExtract is a harmless no-op.
  await expect(
    t.finishAllScheduledFunctions(vi.runAllTimers),
  ).resolves.not.toThrow();

  const people = await t.run((ctx) => ctx.db.query("people").collect());
  expect(people).toHaveLength(1);
  expect(people[0]).toMatchObject({ userId, name: "Grace Hopper", screenshotId });
  expect(await t.run((ctx) => ctx.db.get("captures", captureId))).toBeNull();
});

test("acceptManualCapture refuses a ready capture", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await expect(
    as.mutation(api.captures.acceptManualCapture, {
      captureId,
      name: "Ada Lovelace",
    }),
  ).rejects.toThrow("Capture is not ready");
});

test("acceptManualCapture requires a non-empty name", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await expect(
    as.mutation(api.captures.acceptManualCapture, {
      captureId,
      name: "   ",
    }),
  ).rejects.toThrow("Name is required");
  // The capture is untouched -- still there to try again.
  expect(
    (await t.run((ctx) => ctx.db.get("captures", captureId)))?.status,
  ).toBe("failed");
});

test("another user cannot manually accept my capture", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const me = await asNewUser(t);
  const other = await asNewUser(t);
  const captureId = await me.as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await expect(
    other.as.mutation(api.captures.acceptManualCapture, {
      captureId,
      name: "Ada Lovelace",
    }),
  ).rejects.toThrow("Capture not found");
});

test("acceptManualCapture throttles a burst past the per-minute limit", async () => {
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);

  // Seed failed captures directly: createCapture has its own tighter limit,
  // so it cannot mint the 31 rows this window's cap needs.
  const captureIds: Id<"captures">[] = [];
  await t.run(async (ctx) => {
    for (let i = 0; i < 31; i++) {
      captureIds.push(
        await ctx.db.insert("captures", {
          userId,
          screenshotId,
          status: "failed",
        }),
      );
    }
  });

  for (let i = 0; i < 30; i++) {
    await as.mutation(api.captures.acceptManualCapture, {
      captureId: captureIds[i],
      name: "Ada Lovelace",
    });
  }
  await expect(
    as.mutation(api.captures.acceptManualCapture, {
      captureId: captureIds[30],
      name: "Ada Lovelace",
    }),
  ).rejects.toThrow("Too many requests -- please wait a moment");
});

// ------------------------------------------------------------ janitor crons

test("sweepStuckCaptures fails a pending capture stuck past the threshold", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  // Never let the scheduled extract action resolve it -- simulating an
  // extraction that got killed (timeout, redeploy) rather than throwing.

  vi.setSystemTime(Date.now() + 16 * 60_000);
  const swept = await t.mutation(internal.captures.sweepStuckCaptures, {});

  expect(swept).toBe(1);
  const capture = await t.run((ctx) => ctx.db.get("captures", captureId));
  expect(capture?.status).toBe("failed");
  expect(capture?.error).toBe(
    "Could not read this screenshot -- you can retry",
  );
});

test("sweepStuckCaptures leaves a fresh pending capture alone", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });

  const swept = await t.mutation(internal.captures.sweepStuckCaptures, {});

  expect(swept).toBe(0);
  const capture = await t.run((ctx) => ctx.db.get("captures", captureId));
  expect(capture?.status).toBe("pending");
});

test("sweepStuckCaptures never touches a ready or failed capture, however old", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);
  const readyId = await t.run((ctx) =>
    ctx.db.insert("captures", {
      userId,
      screenshotId,
      status: "ready",
      extracted: { platform: "x", name: "Ada Lovelace" },
    }),
  );
  const failedId = await t.run((ctx) =>
    ctx.db.insert("captures", {
      userId,
      screenshotId,
      status: "failed",
      error: "Could not read a profile in this screenshot",
    }),
  );

  vi.setSystemTime(Date.now() + 60 * 60_000);
  const swept = await t.mutation(internal.captures.sweepStuckCaptures, {});

  expect(swept).toBe(0);
  expect(
    (await t.run((ctx) => ctx.db.get("captures", readyId)))?.status,
  ).toBe("ready");
  expect(
    (await t.run((ctx) => ctx.db.get("captures", failedId)))?.status,
  ).toBe("failed");
});

test("sweepOrphanedUploads deletes an old blob no capture or person references", async () => {
  const t = convexTest(schema, modules);
  const screenshotId = await seedScreenshot(t);

  vi.setSystemTime(Date.now() + 61 * 60_000);
  const swept = await t.mutation(internal.captures.sweepOrphanedUploads, {});

  expect(swept).toBe(1);
  expect(await t.run((ctx) => ctx.storage.getUrl(screenshotId))).toBeNull();
});

test("sweepOrphanedUploads never deletes a blob referenced by a capture", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);
  await as.mutation(api.captures.createCapture, { screenshotId });

  vi.setSystemTime(Date.now() + 61 * 60_000);
  const swept = await t.mutation(internal.captures.sweepOrphanedUploads, {});

  expect(swept).toBe(0);
  expect(
    await t.run((ctx) => ctx.storage.getUrl(screenshotId)),
  ).not.toBeNull();
});

test("sweepOrphanedUploads never deletes a blob referenced by a person", async () => {
  const t = convexTest(schema, modules);
  const { userId } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);
  await t.run((ctx) =>
    ctx.db.insert("people", {
      userId,
      name: "Ada Lovelace",
      updatedAt: Date.now(),
      screenshotId,
    }),
  );

  vi.setSystemTime(Date.now() + 61 * 60_000);
  const swept = await t.mutation(internal.captures.sweepOrphanedUploads, {});

  expect(swept).toBe(0);
  expect(
    await t.run((ctx) => ctx.storage.getUrl(screenshotId)),
  ).not.toBeNull();
});

test("sweepOrphanedUploads never deletes a blob referenced by a profile photo", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const screenshotId = await seedScreenshot(t);
  await as.mutation(api.profiles.updateMyProfile, {
    name: "Ada Lovelace",
    photoStorageId: screenshotId,
  });

  vi.setSystemTime(Date.now() + 61 * 60_000);
  const swept = await t.mutation(internal.captures.sweepOrphanedUploads, {});

  expect(swept).toBe(0);
  expect(
    await t.run((ctx) => ctx.storage.getUrl(screenshotId)),
  ).not.toBeNull();
});

test("sweepOrphanedUploads never deletes a blob referenced by a person photo", async () => {
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const photoId = await seedScreenshot(t);
  await as.mutation(api.people.addPersonWithOutcome, {
    name: "Ada Lovelace",
    photoStorageId: photoId,
    contactHandles: [{ platform: "phone", value: "unlisted1" }],
    context: "met before this test",
  });

  vi.setSystemTime(Date.now() + 61 * 60_000);
  const swept = await t.mutation(internal.captures.sweepOrphanedUploads, {});

  expect(swept).toBe(0);
  expect(await t.run((ctx) => ctx.storage.getUrl(photoId))).not.toBeNull();
});

test("sweepOrphanedUploads leaves a young unreferenced blob alone", async () => {
  const t = convexTest(schema, modules);
  const screenshotId = await seedScreenshot(t);

  const swept = await t.mutation(internal.captures.sweepOrphanedUploads, {});

  expect(swept).toBe(0);
  expect(
    await t.run((ctx) => ctx.storage.getUrl(screenshotId)),
  ).not.toBeNull();
});

test("sweepOrphanedUploads only deletes the orphan when an old orphan and an old referenced blob coexist", async () => {
  // A single-blob sweep can't prove the loop distinguishes candidates --
  // this proves it keeps scanning past a referenced blob to reach an orphan
  // (and stops correctly once it hits one too young to qualify).
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const orphanId = await seedScreenshot(t);
  const referencedId = await seedScreenshot(t);
  await as.mutation(api.captures.createCapture, {
    screenshotId: referencedId,
  });

  vi.setSystemTime(Date.now() + 61 * 60_000);
  const stillYoungId = await seedScreenshot(t);
  const swept = await t.mutation(internal.captures.sweepOrphanedUploads, {});

  expect(swept).toBe(1);
  expect(await t.run((ctx) => ctx.storage.getUrl(orphanId))).toBeNull();
  expect(
    await t.run((ctx) => ctx.storage.getUrl(referencedId)),
  ).not.toBeNull();
  expect(
    await t.run((ctx) => ctx.storage.getUrl(stillYoungId)),
  ).not.toBeNull();
});

test("sweepOrphanedUploads makes progress past a wall of referenced blobs", async () => {
  // Regression guard for the reviewer's major: without a persisted
  // watermark, every run re-reads the same oldest batch, so an orphan
  // behind a wall of referenced blobs would never be reached.
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const wall1 = await seedScreenshot(t);
  const wall2 = await seedScreenshot(t);
  stubOpenAI({ failExtraction: true });
  await as.mutation(api.captures.createCapture, { screenshotId: wall1 });
  await as.mutation(api.captures.createCapture, { screenshotId: wall2 });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  const orphan = await seedScreenshot(t);

  vi.setSystemTime(Date.now() + 61 * 60_000);
  // Batch of 2: the first run can only see the two referenced wall blobs.
  const first = await t.mutation(internal.captures.sweepOrphanedUploads, {
    batchSize: 2,
  });
  expect(first).toBe(0);
  // The second run must RESUME past the wall and reach the orphan.
  const second = await t.mutation(internal.captures.sweepOrphanedUploads, {
    batchSize: 2,
  });
  expect(second).toBe(1);
  expect(await t.run((ctx) => ctx.storage.getUrl(orphan))).toBeNull();
  expect(await t.run((ctx) => ctx.storage.getUrl(wall1))).not.toBeNull();
});

// ------------------------------------------- identity index on acceptance

// Both accept paths insert a person directly, bypassing addPerson, so they
// own the personHandles invariant themselves: without it, re-sharing the same
// account later twins the person.
async function handleRows(t: ReturnType<typeof convexTest>) {
  return await t.run((ctx) => ctx.db.query("personHandles").take(20));
}

test("acceptCapture indexes the extracted handle so a later share finds the same person", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const personId = await acceptCaptureId(as, { captureId });

  const person = await t.run((ctx) => ctx.db.get("people", personId));
  // The display array keeps the legacy scalars company; neither replaces
  // the other while the legacy pair is still read by the embed text.
  expect(displayOnly(person?.contactHandles)).toEqual([{ platform: "x", value: "ada_l" }]);
  expect(person?.platform).toBe("x");
  expect(await handleRows(t)).toMatchObject([
    { userId, personId, platform: "x", valueKey: "ada_l" },
  ]);

  const shared = await as.mutation(api.people.saveSharedProfile, {
    platform: "x",
    handleValue: "ada_l",
    profileUrl: "https://x.com/ada_l",
    name: "Ada Lovelace",
  });
  expect(shared).toEqual({
    status: "already",
    personId,
    noteTruncated: false,
    handleDropped: false,
  });
});

test("an extracted handle folds to one identity however the model cased it", async () => {
  stubOpenAI({
    extraction: { ...EXTRACTION, platform: " X ", handle: "@Ada_L" },
  });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const personId = await acceptCaptureId(as, { captureId });

  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(displayOnly(person?.contactHandles)).toEqual([{ platform: "x", value: "Ada_L" }]);
  expect(await handleRows(t)).toMatchObject([
    { platform: "x", valueKey: "ada_l" },
  ]);
  const shared = await as.mutation(api.people.saveSharedProfile, {
    platform: "x",
    handleValue: "ada_l",
    profileUrl: "https://x.com/ada_l",
    name: "Ada Lovelace",
  });
  expect(shared.personId).toBe(personId);
});

// ------------------------------------------------------------ provenance

test("acceptCapture stores the extracted handle with source imported", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const personId = await acceptCaptureId(as, { captureId });
  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person?.contactHandles?.[0].source).toBe("imported");
  expect(person?.contactHandles?.[0].addedAt).toEqual(expect.any(Number));
});

test("acceptManualCapture defaults an unstated handle source to typed", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const personId = await acceptManualCaptureId(as, {
    captureId,
    name: "Mai Tran",
    contactHandle: { platform: "instagram", value: "mai.makes" },
  });
  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person?.contactHandles?.[0].source).toBe("typed");
});

// The gap this closes: insertCaptureHandle and foldContactHandle used to
// write a personHandles row with no ownership check at all, so a second
// screenshot of an account already saved made a second person for it.
test("acceptCapture attaches to an existing owner instead of making a second person", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const owner = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Ada Lovelace",
    context: "met at the compiler talk",
    contactHandles: [{ platform: "x", value: "ada_l" }],
  });
  if (owner.status !== "created") throw new Error("unreachable");

  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const result = await as.mutation(api.captures.acceptCapture, {
    captureId,
    context: "screenshotted her profile too",
  });
  expect(result.status).toBe("attached");
  if (result.status !== "attached" && result.status !== "already") {
    throw new Error("unreachable");
  }
  expect(result.personId).toBe(owner.personId);

  const people = await t.run((ctx) =>
    ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect(),
  );
  expect(people).toHaveLength(1);
  const person = await t.run((ctx) => ctx.db.get("people", owner.personId));
  expect(person?.context).toBe(
    "met at the compiler talk\nscreenshotted her profile too",
  );
  // The capture is consumed on attach exactly like it is on create.
  expect(await t.run((ctx) => ctx.db.get("captures", captureId))).toBeNull();
});

// The attach path used to copy only the note and the handle: headline, bio,
// link and the screenshot this capture proves all got silently dropped, and
// the new blob orphaned with nothing pointing at it. Fixed to fill each
// EMPTY field on the owner from what this capture extracted.
test("acceptCapture fills the owner's empty headline, bio and screenshot from the capture", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const owner = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Ada Lovelace",
    context: "met at the compiler talk",
    contactHandles: [{ platform: "x", value: "ada_l" }],
  });
  if (owner.status !== "created") throw new Error("unreachable");
  const before = await t.run((ctx) => ctx.db.get("people", owner.personId));
  expect(before?.headline).toBeUndefined();
  expect(before?.bio).toBeUndefined();
  expect(before?.screenshotId).toBeUndefined();

  const screenshotId = await seedScreenshot(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await as.mutation(api.captures.acceptCapture, {
    captureId,
    context: "screenshotted her profile too",
  });

  const after = await t.run((ctx) => ctx.db.get("people", owner.personId));
  expect(after?.headline).toBe(EXTRACTION.headline);
  expect(after?.bio).toBe(EXTRACTION.bio);
  expect(after?.screenshotId).toBe(screenshotId);
});

test("acceptCapture never overwrites what the owner already has -- the new screenshot just orphans", async () => {
  stubOpenAI({ extraction: EXTRACTION });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const owner = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Ada Lovelace",
    context: "met at the compiler talk",
    contactHandles: [{ platform: "x", value: "ada_l" }],
  });
  if (owner.status !== "created") throw new Error("unreachable");
  const ownerScreenshot = await seedScreenshot(t);
  await t.run((ctx) =>
    ctx.db.patch("people", owner.personId, {
      headline: "Already knew this",
      bio: "Already knew this too",
      screenshotId: ownerScreenshot,
    }),
  );

  const newScreenshotId = await seedScreenshot(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: newScreenshotId,
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await as.mutation(api.captures.acceptCapture, {
    captureId,
    context: "screenshotted her profile too",
  });

  // Nothing the owner already had for themselves was overwritten -- the new
  // screenshot legitimately orphans rather than displacing the one already
  // anchoring this person's memory.
  const after = await t.run((ctx) => ctx.db.get("people", owner.personId));
  expect(after?.headline).toBe("Already knew this");
  expect(after?.bio).toBe("Already knew this too");
  expect(after?.screenshotId).toBe(ownerScreenshot);
});

test("acceptManualCapture fills the owner's empty headline and link, never overwrites what is already there", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const withNothing = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "gave me her card",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });
  if (withNothing.status !== "created") throw new Error("unreachable");

  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  await as.mutation(api.captures.acceptManualCapture, {
    captureId,
    name: "Mai (misspelled)",
    context: "screenshotted the same profile again",
    headline: "Ceramicist",
    link: "https://mai.example",
    contactHandle: { platform: "instagram", value: "mai.makes" },
  });

  const filled = await t.run((ctx) => ctx.db.get("people", withNothing.personId));
  expect(filled?.headline).toBe("Ceramicist");
  expect(filled?.link).toBe("https://mai.example");

  // A second person who already has both: neither field moves.
  const withBoth = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Binh Le",
    context: "met at the ceramics market",
    contactHandles: [{ platform: "instagram", value: "binh.le" }],
  });
  if (withBoth.status !== "created") throw new Error("unreachable");
  await t.run((ctx) =>
    ctx.db.patch("people", withBoth.personId, {
      headline: "Already a potter",
      link: "https://binh.example",
    }),
  );
  const secondCaptureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  await as.mutation(api.captures.acceptManualCapture, {
    captureId: secondCaptureId,
    name: "Binh (misspelled)",
    context: "screenshotted again",
    headline: "A different headline",
    link: "https://someone-elses-link.example",
    contactHandle: { platform: "instagram", value: "binh.le" },
  });
  const untouched = await t.run((ctx) => ctx.db.get("people", withBoth.personId));
  expect(untouched?.headline).toBe("Already a potter");
  expect(untouched?.link).toBe("https://binh.example");
});

test("acceptManualCapture attaches to an existing owner instead of making a second person", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const owner = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Mai Tran",
    context: "gave me her card",
    contactHandles: [{ platform: "instagram", value: "mai.makes" }],
  });
  if (owner.status !== "created") throw new Error("unreachable");

  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const result = await as.mutation(api.captures.acceptManualCapture, {
    captureId,
    name: "Mai (misspelled)",
    context: "screenshotted the same profile again",
    contactHandle: { platform: "instagram", value: "mai.makes" },
  });
  expect(result.status).toBe("attached");
  if (result.status !== "attached" && result.status !== "already") {
    throw new Error("unreachable");
  }
  expect(result.personId).toBe(owner.personId);

  const people = await t.run((ctx) =>
    ctx.db
      .query("people")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect(),
  );
  expect(people).toHaveLength(1);
  expect(people[0].name).toBe("Mai Tran");
});

// S3: an id-preferred merge whose new value already belongs to somebody
// else refuses rather than double-indexing that value. Unlike an attended
// save, nobody is present here to resolve the refusal, so this falls
// through to create instead of stranding the capture -- the same doctrine
// saveSharedProfile's heldDifferently already follows.
// Was "falls through to create" -- that used to mint a THIRD person carrying
// A's id and B's username, double-indexing B's valueKey. The id says this
// capture is A; the value it carries already, provably, belongs to B. Nobody
// is present to resolve that, so this refuses instead of guessing: nothing
// written, capture stays in triage for a human to sort out later.
test("acceptManualCapture refuses rather than minting a corrupt third identity when an id-preferred merge would collide with someone else's handle", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const b = await as.mutation(api.people.addPersonWithOutcome, {
    name: "New Person",
    context: "met at the market",
    contactHandles: [{ platform: "x", value: "newhandle" }],
  });
  if (b.status !== "created") throw new Error("unreachable");
  const a = await as.mutation(api.people.addPersonWithOutcome, {
    name: "Ada Lovelace",
    context: "met at the compiler talk",
    contactHandles: [
      { platform: "x", value: "oldhandle", platformId: "x-id-1" },
    ],
  });
  if (a.status !== "created") throw new Error("unreachable");

  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const result = await as.mutation(api.captures.acceptManualCapture, {
    captureId,
    name: "Ada (new handle)",
    context: "screenshotted her renamed profile",
    contactHandle: { platform: "x", value: "newhandle", platformId: "x-id-1" },
  });

  // personId names the id-matched owner (A) -- the person the capture claims
  // to be -- not the value's actual owner (B), the same "who does the id say
  // this is" convention saveSharedProfile's own conflict outcome uses.
  expect(result).toEqual({ status: "conflict", personId: a.personId });

  // The capture is still in triage, not deleted -- a human can resolve it,
  // and a retry never redrains into the same corruption.
  expect(await t.run((ctx) => ctx.db.get("captures", captureId))).not.toBeNull();

  // Neither existing person touched, and no third person minted.
  const aAfter = await t.run((ctx) => ctx.db.get("people", a.personId));
  expect(aAfter?.contactHandles).toEqual([
    expect.objectContaining({ platform: "x", value: "oldhandle" }),
  ]);
  const bAfter = await t.run((ctx) => ctx.db.get("people", b.personId));
  expect(bAfter?.contactHandles).toEqual([
    expect.objectContaining({ platform: "x", value: "newhandle" }),
  ]);
  expect(await t.run((ctx) => ctx.db.query("people").collect())).toHaveLength(2);
});

// acceptCapture's own fold never learns a platformId -- the extracted
// validator (schema.ts) has no such field, since vision extraction cannot
// read a numeric platform id off a screenshot -- so the id-preferred
// rename-collision this fixes can only be reached through acceptManualCapture
// today (a human can type an id-carrying handle at triage). tryAttachToOwner
// is still the shared seam both mutations call, so the fix defends
// acceptCapture too the moment any caller starts passing one through.

test("a capture with no visible handle stays name-only", async () => {
  // Honest, not a bug: a screenshot that shows no handle names a person and
  // nothing more. An invented index row would be a fabricated identity.
  stubOpenAI({ extraction: { ...EXTRACTION, handle: "  " } });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const personId = await acceptCaptureId(as, { captureId });

  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person?.contactHandles).toBeUndefined();
  expect(await handleRows(t)).toHaveLength(0);
});

test("acceptManualCapture indexes a typed handle in the same transaction", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { userId, as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const personId = await acceptManualCaptureId(as, {
    captureId,
    name: "Mai Tran",
    contactHandle: { platform: " Instagram ", value: "@Mai.Makes" },
  });

  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(displayOnly(person?.contactHandles)).toEqual([
    { platform: "instagram", value: "Mai.Makes" },
  ]);
  expect(await handleRows(t)).toMatchObject([
    { userId, personId, platform: "instagram", valueKey: "mai.makes" },
  ]);

  const shared = await as.mutation(api.people.saveSharedProfile, {
    platform: "instagram",
    handleValue: "mai.makes",
    profileUrl: "https://instagram.com/mai.makes",
    name: "Mai Tran",
  });
  expect(shared.status).toBe("already");
  expect(shared.personId).toBe(personId);
});

test("a manually named capture without a handle stays name-only", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  const personId = await acceptManualCaptureId(as, {
    captureId,
    name: "Mai Tran",
  });

  const person = await t.run((ctx) => ctx.db.get("people", personId));
  expect(person?.contactHandles).toBeUndefined();
  expect(await handleRows(t)).toHaveLength(0);
});

test("acceptManualCapture refuses a blank typed handle", async () => {
  // The human is present here, unlike on the extraction path: a blank field
  // is a client bug worth surfacing, not something to silently drop.
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await expect(
    as.mutation(api.captures.acceptManualCapture, {
      captureId,
      name: "Mai Tran",
      contactHandle: { platform: "instagram", value: " @ " },
    }),
  ).rejects.toThrow("A handle cannot be blank");
  await expect(
    as.mutation(api.captures.acceptManualCapture, {
      captureId,
      name: "Mai Tran",
      contactHandle: { platform: "  ", value: "mai.makes" },
    }),
  ).rejects.toThrow("A platform cannot be blank");
});

// Strict where acceptCapture is lenient (see below): a human is typing this
// in, so a phone/whatsapp value with no digit at all is a client bug worth
// surfacing rather than something to silently drop.
test("acceptManualCapture refuses a typed phone value with no digit at all", async () => {
  stubOpenAI({ failExtraction: true });
  const t = convexTest(schema, modules);
  const { as } = await asNewUser(t);
  const captureId = await as.mutation(api.captures.createCapture, {
    screenshotId: await seedScreenshot(t),
  });
  await t.finishAllScheduledFunctions(vi.runAllTimers);

  await expect(
    as.mutation(api.captures.acceptManualCapture, {
      captureId,
      name: "Alice",
      contactHandle: { platform: "phone", value: "unknown" },
    }),
  ).rejects.toThrow("A phone number needs at least one digit");
});

test("sweepOrphanedUploads resets its watermark after an exhausted pass", async () => {
  const t = convexTest(schema, modules);
  const first = await seedScreenshot(t);
  vi.setSystemTime(Date.now() + 61 * 60_000);
  // Exhausted pass (fewer candidates than the batch) deletes and resets.
  expect(
    await t.mutation(internal.captures.sweepOrphanedUploads, { batchSize: 2 }),
  ).toBe(1);
  // A NEW old orphan created after the reset must be reachable on the next
  // cycle -- proving the watermark went back to the start.
  const second = await seedScreenshot(t);
  vi.setSystemTime(Date.now() + 61 * 60_000);
  expect(
    await t.mutation(internal.captures.sweepOrphanedUploads, { batchSize: 2 }),
  ).toBe(1);
  expect(await t.run((ctx) => ctx.storage.getUrl(second))).toBeNull();
  expect(first).not.toBe(second);
});
