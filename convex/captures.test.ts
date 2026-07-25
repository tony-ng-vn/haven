/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
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

  const personId = await as.mutation(api.captures.acceptCapture, {
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

  const personId = await as.mutation(api.people.addPerson, { name: "Maya" });
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

  const personId = await as.mutation(api.captures.acceptManualCapture, {
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

  const personId = await as.mutation(api.captures.acceptManualCapture, {
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

  const personId = await as.mutation(api.captures.acceptManualCapture, {
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
  await as.mutation(api.people.addPerson, {
    name: "Ada Lovelace",
    photoStorageId: photoId,
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
